// sevenzip_bridge.cpp -- C bridge between 7-zip C++ internals and Swift.
// All C++ exceptions are caught at the extern "C" boundary.

#include "StdAfx.h"

#include "include/sevenzip_bridge.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <deque>
#include <vector>
#include <set>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <copyfile.h>
#include <sys/xattr.h>
#include <utility>
#include <cerrno>

#include "Common/MyWindows.h"
#include "Common/MyCom.h"
#include "Common/MyString.h"
#include "Common/StringConvert.h"
#include "Common/UTFConvert.h"
#include "Common/IntToString.h"
#include "Common/Wildcard.h"   // SplitPathToParts -- already-linked 7-Zip util

#include "Windows/FileDir.h"
#include "Windows/FileFind.h"
#include "Windows/FileName.h"
#include "Windows/PropVariant.h"
#include "Windows/PropVariantConv.h"

#include "7zip/Common/FileStreams.h"
#include "7zip/Common/StreamUtils.h"

#include "7zip/Archive/IArchive.h"
#include "7zip/IPassword.h"
#include "7zip/MyVersion.h"   // MY_VERSION -- tracks the vendored submodule

static const GUID IID_IInArchive_Local = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x06, 0x00, 0x60, 0x00, 0x00}
};

// IInArchiveGetStream: archive group (6), sub 0x40
static const GUID IID_IInArchiveGetStream_Local = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x06, 0x00, 0x40, 0x00, 0x00}
};

// IInStream: stream group (3), sub 0x03
static const GUID IID_IInStream_Local = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x03, 0x00, 0x03, 0x00, 0x00}
};

// IArchiveGetRawProps: archive group (6), sub 0x70
static const GUID IID_IArchiveGetRawProps_Local = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x06, 0x00, 0x70, 0x00, 0x00}
};

// --- External functions from ArchiveExports.cpp / CodecExports.cpp ---
STDAPI GetNumberOfFormats(UINT32 *numFormats);
STDAPI GetHandlerProperty2(UInt32 formatIndex, PROPID propID, PROPVARIANT *value);
STDAPI CreateArchiver(const GUID *clsid, const GUID *iid, void **outObject);

// --- Helpers ---

// Force 7-Zip's narrow<->wide string conversions to use UTF-8.
//
// 7-Zip's load-time constructor (DllExports2.cpp) sets the global
// `g_ForceToUTF8` from `IsNativeUTF8()`, which probes the C locale. In a macOS
// GUI/test process that locale is "C"/"POSIX", so the flag becomes false and
// `us2fs()` falls back to wcstombs() -- which cannot represent non-ASCII bytes
// and replaces them with '_'. macOS filesystem paths are always UTF-8, so we
// force the flag on. Shared with the write bridge.
void sz_force_utf8_paths(void) {
    g_ForceToUTF8 = true;
}

static std::string UStringToUTF8(const UString &src) {
    AString dest;
    ConvertUnicodeToUTF8(src, dest);
    return std::string(dest.Ptr(), dest.Len());
}

static std::string PropVariantToUTF8(const NWindows::NCOM::CPropVariant &prop) {
    if (prop.vt == VT_BSTR && prop.bstrVal) {
        UString us(prop.bstrVal);
        return UStringToUTF8(us);
    }
    return "";
}

static int64_t FileTimeToUnixEpoch(const FILETIME &ft) {
    // FILETIME: 100-nanosecond intervals since 1601-01-01
    // Unix epoch: seconds since 1970-01-01
    // Difference: 11644473600 seconds
    UInt64 ticks = ((UInt64)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    if (ticks == 0) return -1;
    return (int64_t)(ticks / 10000000ULL - 11644473600ULL);
}

// --- Archive Handle ---

struct SZArchiveLevel {
    CMyComPtr<IInArchive> archive;
    CMyComPtr<IInStream> stream;  // stream this archive was opened from
};

struct SZArchiveHandle {
    CMyComPtr<IInStream> fileStream;           // original file stream
    std::vector<SZArchiveLevel> levels;        // [0]=outermost, back()=innermost
    CMyComPtr<IArchiveGetRawProps> rawProps;    // cached; non-null if archive implements it
    bool isTree = false;                       // true only if kpidIsTree is set
    std::deque<std::string> storedStrings;     // deque: stable pointers on push_back
    UInt32 numItems;
    std::string password;
    bool hasPassword = false;

    const char* storeString(const std::string &s) {
        storedStrings.push_back(s);
        return storedStrings.back().c_str();
    }

    IInArchive* activeArchive() const {
        return levels.back().archive;
    }
};

// --- Volume callback for split/multi-volume archives ---

class COpenVolumeCallback final :
    public IArchiveOpenVolumeCallback,
    public IArchiveOpenCallback,
    public ICryptoGetTextPassword,
    public CMyUnknownImp
{
    Z7_COM_UNKNOWN_IMP_3(IArchiveOpenVolumeCallback, IArchiveOpenCallback, ICryptoGetTextPassword)

    FString _basePath;
    FString _fileName;
    std::string _password;
    bool _hasPassword = false;

public:
    /// Set when a handler asked for a password while opening. Formats that
    /// encrypt their header (7z -mhe=on, RAR -hp) cannot even be listed
    /// without one, and a failed open is otherwise indistinguishable from
    /// "not an archive".
    bool passwordRequested = false;

    void SetPassword(const char *password) {
        if (password) {
            _password = password;
            _hasPassword = true;
        } else {
            _password.clear();
            _hasPassword = false;
        }
    }

    Z7_COM7F_IMF(CryptoGetTextPassword(BSTR *password)) {
        passwordRequested = true;
        if (!_hasPassword)
            return E_ABORT;
        AString aPassword(_password.c_str());
        UString uPassword;
        ConvertUTF8ToUnicode(aPassword, uPassword);
        *password = ::SysAllocString((const OLECHAR *)(const wchar_t *)uPassword);
        return S_OK;
    }

    void SetFilePath(const FString &path) {
        int pos = path.ReverseFind_PathSepar();
        if (pos >= 0) {
            _basePath = path.Left(pos + 1);
            _fileName = path.Ptr(pos + 1);
        } else {
            _basePath.Empty();
            _fileName = path;
        }
    }

    Z7_COM7F_IMF(GetProperty(PROPID propID, PROPVARIANT *value)) {
        if (propID == kpidName) {
            NWindows::NCOM::CPropVariant prop(fs2us(_fileName));
            prop.Detach(value);
            return S_OK;
        }
        return S_OK;
    }

    Z7_COM7F_IMF(GetStream(const wchar_t *name, IInStream **inStream)) {
        *inStream = nullptr;
        UString uName(name);
        FString fName = us2fs(uName);
        FString fullPath = _basePath + fName;

        NWindows::NFile::NFind::CFileInfo fi;
        if (!fi.Find_FollowLink(fullPath) || fi.IsDir())
            return S_FALSE;

        CInFileStream *fileSpec = new CInFileStream;
        CMyComPtr<IInStream> streamRef = fileSpec;
        if (!fileSpec->Open(fullPath))
            return S_FALSE;

        *inStream = streamRef.Detach();
        return S_OK;
    }

    Z7_COM7F_IMF(SetTotal(const UInt64 *, const UInt64 *)) { return S_OK; }
    Z7_COM7F_IMF(SetCompleted(const UInt64 *, const UInt64 *)) { return S_OK; }
};

// --- Format probing helper ---

/// Try all registered formats against the given seekable stream.
/// Returns S_OK on success with archiveOut set, S_FALSE if no format matched.
static HRESULT tryOpenStream(
    IInStream *stream,
    CMyComPtr<IInArchive> &archiveOut,
    IArchiveOpenCallback *callback = nullptr)
{
    UInt32 numFormats = 0;
    GetNumberOfFormats(&numFormats);

    for (UInt32 i = 0; i < numFormats; i++) {
        NWindows::NCOM::CPropVariant propClassID;
        GetHandlerProperty2(i, NArchive::NHandlerPropID::kClassID, &propClassID);
        if (propClassID.vt != VT_BSTR || !propClassID.bstrVal)
            continue;

        GUID classID;
        memcpy(&classID, propClassID.bstrVal, sizeof(GUID));

        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&classID, &IID_IInArchive_Local, (void **)&archive);
        if (hr != S_OK || !archive)
            continue;

        UInt64 newPos;
        stream->Seek(0, STREAM_SEEK_SET, &newPos);

        UInt64 maxCheckStart = 1 << 22; // 4MB
        hr = archive->Open(stream, &maxCheckStart, callback);
        if (hr == S_OK) {
            archiveOut = archive;
            return S_OK;
        }
        archive->Close();
    }
    return S_FALSE;
}

// --- Minimal extract callback ---

class CExtractCallback final :
    public IArchiveExtractCallback,
    public ICryptoGetTextPassword,
    public CMyUnknownImp
{
    Z7_COM_UNKNOWN_IMP_2(IArchiveExtractCallback, ICryptoGetTextPassword)

public:
    CExtractCallback(IInArchive *archive, const FString &destDir,
                     const std::string &password, bool hasPassword,
                     sz_progress_callback progress = nullptr,
                     void *progressContext = nullptr)
        : _archive(archive), _destDir(destDir), _outFileStream(nullptr),
          _password(password), _hasPassword(hasPassword),
          _progress(progress), _progressContext(progressContext) {}

    // IProgress — forwards 7-Zip's byte counters to the bridge consumer.
    // Returning E_ABORT from SetCompleted cancels the whole extraction.
    Z7_COM7F_IMF(SetTotal(UInt64 total)) {
        _total = total;
        return S_OK;
    }
    Z7_COM7F_IMF(SetCompleted(const UInt64 *completeValue)) {
        if (_progress && completeValue) {
            if (!_progress(*completeValue, _total, _progressContext)) {
                aborted = true;
                return E_ABORT;
            }
        }
        return S_OK;
    }

    // IArchiveExtractCallback
    Z7_COM7F_IMF(GetStream(UInt32 index, ISequentialOutStream **outStream, Int32 askExtractMode));
    Z7_COM7F_IMF(PrepareOperation(Int32 /* askExtractMode */)) { return S_OK; }
    Z7_COM7F_IMF(SetOperationResult(Int32 opRes));

    // ICryptoGetTextPassword
    Z7_COM7F_IMF(CryptoGetTextPassword(BSTR *password));

    std::string errorMessage;
    bool aborted = false;
    /// Worst NArchive::NExtract::NOperationResult seen across the entries of
    /// this run, kOK when every entry decoded. 7-Zip reports per-entry failures
    /// through SetOperationResult and *still* returns S_OK from Extract(), so
    /// without this the caller cannot tell a wrong password from a success.
    Int32 failedOpResult = NArchive::NExtract::NOperationResult::kOK;
    /// Extracted files whose name starts with "._", i.e. candidate AppleDouble
    /// sidecars. They cannot be resolved as they arrive: a sidecar may be stored
    /// before the entry it describes, and `._x` sorts before `x`, so that is the
    /// order an archiver walking a directory tends to produce. finishExtract()
    /// drains this once every entry is on disk.
    std::vector<std::string> appleDoubleSidecars;
    /// Every path this extraction created -- files as they finish, directories as
    /// they are made. A sidecar is only ever folded into one of these. The
    /// destination is not always empty: "Extract here" writes straight into a
    /// folder of the user's own files, and "Extract to folder" reuses an existing
    /// folder on a second run. A file already sitting there that happens to match
    /// a sidecar's name is not ours to touch.
    std::set<std::string> extractedPaths;

private:
    /// Creates `dir` and records the levels that did not exist beforehand.
    /// CreateComplexDir is mkdir -p: it reports success on a directory that was
    /// already there, so only a probe before the call can tell ours from the
    /// user's.
    void createDirsRecordingNew(const FString &dir);

    IInArchive *_archive;
    FString _destDir;
    CMyComPtr<ISequentialOutStream> _outFileStream;
    FString _currentFilePath;
    UInt32 _currentMode = 0;         // POSIX mode from kpidPosixAttrib; 0 if unknown
    bool _currentIsSymlink = false;  // entry is a Unix symlink (S_IFLNK)
    bool _currentIsEncrypted = false; // entry is encrypted (kpidEncrypted)
    std::string _password;
    bool _hasPassword;
    sz_progress_callback _progress;
    void *_progressContext;
    UInt64 _total = 0;
};

Z7_COM7F_IMF(CExtractCallback::GetStream(
    UInt32 index, ISequentialOutStream **outStream, Int32 askExtractMode))
{
    *outStream = nullptr;

    // Reset per-entry POSIX state. SetOperationResult only acts when GetStream
    // fills these in below for an actually-extracted file.
    _currentFilePath.Empty();
    _currentMode = 0;
    _currentIsSymlink = false;

    // Remember whether this entry is encrypted: 7z AES carries no password
    // verifier, so a bad password surfaces as a data/CRC error and
    // SetOperationResult has to reinterpret it.
    NWindows::NCOM::CPropVariant propEncrypted;
    _archive->GetProperty(index, kpidEncrypted, &propEncrypted);
    _currentIsEncrypted = (propEncrypted.vt == VT_BOOL
        && propEncrypted.boolVal != VARIANT_FALSE);

    if (askExtractMode != NArchive::NExtract::NAskMode::kExtract)
        return S_OK;

    // Get the path property
    NWindows::NCOM::CPropVariant prop;
    HRESULT hr = _archive->GetProperty(index, kpidPath, &prop);
    if (hr != S_OK) return hr;

    UString filePath;
    if (prop.vt == VT_BSTR && prop.bstrVal)
        filePath = prop.bstrVal;
    else
        filePath = L"unknown";

    // Check if directory
    NWindows::NCOM::CPropVariant propIsDir;
    _archive->GetProperty(index, kpidIsDir, &propIsDir);
    bool isDir = (propIsDir.vt == VT_BOOL && propIsDir.boolVal != VARIANT_FALSE);

    // Sanitize the archive-supplied entry path to prevent Zip-Slip / path
    // traversal. This logic lives in our bridge; we do not modify 7-Zip. Split
    // on path separators (7-Zip's already-linked SplitPathToParts), then drop
    // every "", ".", and ".." segment. A leading "/" produces a leading empty
    // segment, so absolute paths are de-rooted too. The rebuilt path is always
    // relative and cannot escape _destDir.
    UStringVector rawParts;
    SplitPathToParts(filePath, rawParts);

    UString safePath;
    FOR_VECTOR (i, rawParts) {
        const UString &part = rawParts[i];
        if (part.IsEmpty() || part.IsEqualTo(".") || part.IsEqualTo(".."))
            continue;
        if (!safePath.IsEmpty())
            safePath.Add_PathSepar();
        safePath += part;
    }
    if (safePath.IsEmpty())
        safePath = L"unknown";

    FString fullPath = _destDir;
    fullPath += FCHAR_PATH_SEPARATOR;
    fullPath += us2fs(safePath);

    if (isDir) {
        createDirsRecordingNew(fullPath);
        return S_OK;
    }

    // Create parent directory
    int slashPos = (int)fullPath.ReverseFind_PathSepar();
    if (slashPos >= 0) {
        FString parentDir = fullPath.Left((unsigned)slashPos);
        createDirsRecordingNew(parentDir);
    }

    auto *outFileStreamSpec = new COutFileStream;
    CMyComPtr<ISequentialOutStream> outStreamRef(outFileStreamSpec);

    if (!outFileStreamSpec->Create_ALWAYS(fullPath)) {
        errorMessage = "Failed to create output file";
        return E_FAIL;
    }

    // Capture the entry's POSIX mode so SetOperationResult can restore the exec
    // bit and turn symlink entries (7-Zip writes them as a regular file whose
    // contents are the link target) into real symlinks. Absent on non-Unix zips.
    NWindows::NCOM::CPropVariant propPosix;
    _archive->GetProperty(index, kpidPosixAttrib, &propPosix);
    _currentMode = (propPosix.vt == VT_UI4) ? propPosix.ulVal : 0;
    _currentIsSymlink = S_ISLNK(_currentMode);
    _currentFilePath = fullPath;

    _outFileStream = outStreamRef;
    *outStream = outStreamRef.Detach();
    return S_OK;
}

void CExtractCallback::createDirsRecordingNew(const FString &dir) {
    const size_t rootLen = (size_t)_destDir.Len();
    std::string path(dir.Ptr(), (size_t)dir.Len());

    // Already ours, so every level above it is too -- the common case, since
    // consecutive entries share a directory. Nothing left to work out.
    if (path.size() <= rootLen || extractedPaths.count(path) != 0) {
        NWindows::NFile::NDir::CreateComplexDir(dir);
        return;
    }

    // Work out which levels this extraction is about to bring into being, before
    // creating them. A directory already on disk belongs to whoever put it there:
    // the destination can be a folder of the user's own files, and their
    // `Resources/` must not collect metadata out of this archive just because an
    // entry happens to sit inside it. Stops at the first level that exists or is
    // already ours -- everything above that is settled.
    std::vector<std::string> fresh;
    std::string probe = path;
    while (probe.size() > rootLen && extractedPaths.count(probe) == 0) {
        struct stat st;
        if (lstat(probe.c_str(), &st) == 0)
            break;
        fresh.push_back(probe);
        const size_t slash = probe.rfind('/');
        if (slash == std::string::npos || slash < rootLen)
            break;
        probe.erase(slash);
    }

    NWindows::NFile::NDir::CreateComplexDir(dir);

    for (const std::string &level : fresh)
        extractedPaths.insert(level);
}

/// Maps "dir/._name" to the file it describes, "dir/name". Empty when `path` is
/// not of that shape, including a bare "._" with nothing after it -- that would
/// name the parent directory, which must never be an unpack target.
static std::string appleDoubleTargetPath(const std::string &path) {
    const size_t slash = path.rfind('/');
    const size_t base = (slash == std::string::npos) ? 0 : slash + 1;
    if (path.size() < base + 3 || path.compare(base, 2, "._") != 0)
        return std::string();

    std::string target = path;
    target.erase(base, 2);
    return target;
}

/// Name/value of every extended attribute on `path`. False means the set could
/// not be read in full, which is the caller's cue to leave the file alone rather
/// than run something over it that it cannot put back.
static bool readExtendedAttributes(
    const char *path, std::vector<std::pair<std::string, std::string>> &out)
{
    const ssize_t namesLen = listxattr(path, nullptr, 0, XATTR_NOFOLLOW);
    if (namesLen < 0) return false;
    if (namesLen == 0) return true;

    std::string names((size_t)namesLen, '\0');
    if (listxattr(path, &names[0], (size_t)namesLen, XATTR_NOFOLLOW) != namesLen)
        return false;

    // listxattr hands back NUL-separated names in one buffer.
    for (size_t i = 0; i < (size_t)namesLen; ) {
        const std::string name(names.c_str() + i);
        i += name.size() + 1;
        if (name.empty()) continue;

        const ssize_t valueLen = getxattr(path, name.c_str(), nullptr, 0, 0, XATTR_NOFOLLOW);
        if (valueLen < 0) return false;

        std::string value((size_t)valueLen, '\0');
        if (valueLen > 0 &&
            getxattr(path, name.c_str(), &value[0], (size_t)valueLen, 0, XATTR_NOFOLLOW) != valueLen)
            return false;

        out.emplace_back(name, value);
    }
    return true;
}

/// Folds the AppleDouble sidecars collected during extraction into the files and
/// directories they describe, then removes them.
///
/// When macOS has to keep extended attributes and a resource fork somewhere that
/// cannot hold them -- a FAT stick, an SMB share -- it splits them out into a
/// sibling "._name" file. From that point the sidecar is an ordinary file on
/// disk, so any archiver that walks the folder stores it. Nothing here is
/// zip-specific: this runs per entry, for every format the bridge reads, and tar
/// and 7z carry the same sidecars. Left on disk it adds an entry to the
/// extracted tree, and inside a signed .app that breaks the code-signature seal
/// -- macOS then reports the app as damaged.
///
/// "._" is a naming convention, not a reservation, so a real file may be named
/// that way and hold anything. Two guards keep those intact:
///
///   1. The file the sidecar describes has to already exist as a regular file.
///      copyfile() with a missing destination *creates* it from the sidecar,
///      conjuring a file the archive never contained.
///   2. The sidecar is removed only once copyfile() reports success. It rejects
///      a source that is not AppleDouble, which makes it the discriminator too:
///      a plain file that merely starts with "._" fails here and stays put.
///
/// Failures are silent by design. Anything not unpacked is left exactly where
/// the extraction wrote it, so the worst case is the previous behaviour rather
/// than a failed extraction.
static void unpackAppleDoubleSidecars(const std::vector<std::string> &sidecars,
                                      const std::set<std::string> &extractedPaths) {
    for (const std::string &sidecar : sidecars) {
        const std::string target = appleDoubleTargetPath(sidecar);
        if (target.empty())
            continue;

        // Only ever fold into something this extraction wrote. The destination
        // can be a folder that already held the user's files, and one of them
        // matching a sidecar's name by chance is not ours to modify.
        if (extractedPaths.count(target) == 0)
            continue;

        // Directories carry metadata too -- macOS emits `._Resources` next to a
        // bundle's `Resources/` -- so both kinds are valid targets. A symlink is
        // not: copyfile() follows it and would write to whatever it points at.
        struct stat st;
        if (lstat(target.c_str(), &st) != 0)
            continue;
        if (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode))
            continue;

        // COPYFILE_UNPACK *replaces* the target's extended attributes rather than
        // merging into them, so everything the file already wore has to be caught
        // first and put back after. Two different reasons for that:
        //
        //   Quarantine is where macOS keeps Gatekeeper's verdict. Without this an
        //   archive could ship `Evil.app` beside a `._Evil.app` carrying no
        //   quarantine and have this extraction lift it off the bundle -- the
        //   archive deciding its own contents are trusted.
        //
        //   Everything else is the user's. An entry replaces a file that was
        //   already there, the same as `ditto` does, but the plain write keeps that
        //   file's attributes -- so Finder tags and comments survive an overwrite.
        //   They must not stop surviving just because the archive happened to carry
        //   a sidecar for that one file.
        static const char *const kQuarantine = "com.apple.quarantine";
        std::vector<std::pair<std::string, std::string>> before;
        if (!readExtendedAttributes(target.c_str(), before))
            continue;

        bool hadQuarantine = false;
        for (const auto &attr : before)
            hadQuarantine |= (attr.first == kQuarantine);

        if (copyfile(sidecar.c_str(), target.c_str(), nullptr,
                     COPYFILE_UNPACK | COPYFILE_XATTR | COPYFILE_ACL) != 0)
            continue;

        for (const auto &attr : before) {
            // Where both speak, the sidecar wins -- it is describing this very
            // file. Quarantine is the exception: it is the system's verdict on
            // where the file came from, never the archive's to restate.
            if (attr.first != kQuarantine &&
                getxattr(target.c_str(), attr.first.c_str(), nullptr, 0, 0,
                         XATTR_NOFOLLOW) >= 0)
                continue;
            setxattr(target.c_str(), attr.first.c_str(), attr.second.data(),
                     attr.second.size(), 0, XATTR_NOFOLLOW);
        }

        // No quarantine before means none after, whatever the sidecar supplied.
        if (!hadQuarantine)
            removexattr(target.c_str(), kQuarantine, XATTR_NOFOLLOW);

        unlink(sidecar.c_str());
    }
}

// Runs once per entry after its stream is fully written. Restores POSIX metadata
// that the plain file-write above drops: the execute bit (chmod) and symbolic
// links (recreated from the target bytes 7-Zip wrote). Single choke point for all
// three sz_extract_* paths. macOS-only bridge, so FChar == char (UTF-8 paths).
Z7_COM7F_IMF(CExtractCallback::SetOperationResult(Int32 opRes))
{
    // Drop our stream reference so the file is closed/flushed before we read it
    // back, chmod it, or replace it with a symlink.
    _outFileStream.Release();

    if (opRes != NArchive::NExtract::NOperationResult::kOK) {
        // The entry did not decode. Whatever bytes landed on disk are garbage —
        // usually zero of them — so remove the file instead of leaving an empty
        // one that looks like a successful extraction.
        if (!_currentFilePath.IsEmpty())
            unlink(_currentFilePath.Ptr());

        // 7z AES stores no password verifier, so the only sign of a bad
        // password is that the plaintext fails its CRC. On an encrypted entry
        // that is what a wrong password looks like, not a damaged archive.
        if (_currentIsEncrypted &&
            (opRes == NArchive::NExtract::NOperationResult::kDataError ||
             opRes == NArchive::NExtract::NOperationResult::kCRCError))
            opRes = NArchive::NExtract::NOperationResult::kWrongPassword;

        // kWrongPassword wins over any other failure: it is the one the user
        // can actually do something about.
        if (failedOpResult == NArchive::NExtract::NOperationResult::kOK ||
            opRes == NArchive::NExtract::NOperationResult::kWrongPassword)
            failedOpResult = opRes;
        _currentIsSymlink = false;
        _currentMode = 0;
        _currentIsEncrypted = false;
        _currentFilePath.Empty();
        return S_OK;
    }

    if (_currentFilePath.IsEmpty()) {
        _currentIsSymlink = false;
        _currentMode = 0;
        return S_OK;
    }

    const char *path = _currentFilePath.Ptr();

    if (_currentIsSymlink) {
        // 7-Zip wrote the link target as this file's contents; read it back and
        // replace the file with a real symlink.
        std::string target;
        int fd = open(path, O_RDONLY | O_NOFOLLOW);
        if (fd >= 0) {
            char buf[4096];
            ssize_t n;
            while ((n = read(fd, buf, sizeof(buf))) > 0)
                target.append(buf, (size_t)n);
            close(fd);
        }
        while (!target.empty() &&
               (target.back() == '\0' || target.back() == '\n' || target.back() == '\r'))
            target.pop_back();

        if (!target.empty()) {
            unlink(path);
            if (symlink(target.c_str(), path) != 0)
                errorMessage = "Failed to create symbolic link";
        }
    } else if ((_currentMode & 07777) != 0) {
        // Restore stored permissions (notably the exec bit). Only when the archive
        // carried a mode; otherwise keep the default the file was created with.
        if (chmod(path, (mode_t)(_currentMode & 07777)) != 0)
            errorMessage = "Failed to set file permissions";
    }

    // Note a possible AppleDouble sidecar for finishExtract to fold in later. It
    // cannot be resolved here: the file it describes may still be ahead of us in
    // the archive.
    extractedPaths.insert(path);

    if (!_currentIsSymlink && !appleDoubleTargetPath(path).empty())
        appleDoubleSidecars.push_back(path);

    _currentIsSymlink = false;
    _currentMode = 0;
    _currentFilePath.Empty();
    return S_OK;
}

Z7_COM7F_IMF(CExtractCallback::CryptoGetTextPassword(BSTR *password))
{
    if (!_hasPassword) {
        return E_ABORT;
    }
    AString aPassword(_password.c_str());
    UString uPassword;
    ConvertUTF8ToUnicode(aPassword, uPassword);
    *password = ::SysAllocString((const OLECHAR *)(const wchar_t *)uPassword);
    return S_OK;
}

/// Human-readable name for a NArchive::NExtract::NOperationResult value.
static const char *describeOpResult(Int32 opRes) {
    using namespace NArchive::NExtract;
    switch (opRes) {
        case NOperationResult::kUnsupportedMethod: return "Unsupported compression or encryption method";
        case NOperationResult::kDataError:         return "Data error";
        case NOperationResult::kCRCError:          return "CRC error";
        case NOperationResult::kUnavailable:       return "Entry data unavailable";
        case NOperationResult::kUnexpectedEnd:     return "Unexpected end of archive";
        case NOperationResult::kDataAfterEnd:      return "Unexpected data after the end of the archive";
        case NOperationResult::kIsNotArc:          return "Not an archive";
        case NOperationResult::kHeadersError:      return "Archive headers are damaged";
        case NOperationResult::kWrongPassword:     return "Wrong password";
        default:                                   return "Extraction failed";
    }
}

/// Turns an Extract() call plus the callback's recorded per-entry result into a
/// bridge result code. Shared by all three sz_extract_* entry points so none of
/// them can forget to look at the per-entry failures.
static int finishExtract(CExtractCallback *callback, HRESULT hr, char **error_out) {
    if (callback->aborted || hr == E_ABORT)
        return SZ_EXTRACT_ABORTED;

    // Every entry is on disk now, so a sidecar and the file it describes have
    // both landed whichever order the archive stored them in. Runs even when an
    // entry failed: the files that did extract should still come out complete.
    unpackAppleDoubleSidecars(callback->appleDoubleSidecars, callback->extractedPaths);

    const Int32 opRes = callback->failedOpResult;
    const bool entryFailed = opRes != NArchive::NExtract::NOperationResult::kOK;

    if (hr == S_OK && !entryFailed && callback->errorMessage.empty())
        return SZ_EXTRACT_OK;

    if (error_out) {
        std::string msg = entryFailed ? describeOpResult(opRes)
            : (callback->errorMessage.empty() ? "Extraction failed"
                                              : callback->errorMessage);
        *error_out = strdup(msg.c_str());
    }

    return opRes == NArchive::NExtract::NOperationResult::kWrongPassword
        ? SZ_EXTRACT_WRONG_PASSWORD : SZ_EXTRACT_FAILED;
}

// --- Bridge Implementation ---

extern "C" {

SZArchiveRef sz_open(const char *path, const char *password,
                     bool *needs_password_out, char **error_out) {
    if (needs_password_out) *needs_password_out = false;
    try {
        // Force 7-Zip to treat all narrow<->wide path conversions as UTF-8.
        // On macOS the filesystem encoding is always UTF-8, but 7-Zip's
        // load-time constructor (DllExports2.cpp) sets g_ForceToUTF8 based on
        // the C locale, which is "C"/"POSIX" in a GUI/test process. That makes
        // us2fs() route through wcstombs(), mangling non-ASCII path bytes into
        // '_' so archives with UTF-8 names (e.g. utf_你好.zip) fail to open.
        sz_force_utf8_paths();

        auto *handle = new SZArchiveHandle();
        if (password) {
            handle->password = password;
            handle->hasPassword = true;
        }

        // Open the file stream
        auto *fileStreamSpec = new CInFileStream;
        handle->fileStream = fileStreamSpec;
        FString fpath = us2fs(UString());
        {
            AString apath(path);
            UString upath;
            ConvertUTF8ToUnicode(apath, upath);
            fpath = us2fs(upath);
        }

        if (!fileStreamSpec->Open(fpath)) {
            if (error_out)
                *error_out = strdup("Failed to open file");
            delete handle;
            return nullptr;
        }

        // Create a volume callback so SplitHandler can discover sibling
        // volume files (.002, .003, ...) by name-pattern probing. It also
        // answers header-password requests (7z -mhe=on, RAR -hp).
        COpenVolumeCallback *volCallbackSpec = new COpenVolumeCallback;
        CMyComPtr<IArchiveOpenCallback> volCallback = volCallbackSpec;
        volCallbackSpec->SetFilePath(fpath);
        volCallbackSpec->SetPassword(password);

        // Try each registered format on the file stream
        CMyComPtr<IInArchive> firstArchive;
        HRESULT hr = tryOpenStream(handle->fileStream, firstArchive, volCallback);
        if (hr != S_OK || !firstArchive) {
            if (needs_password_out)
                *needs_password_out = volCallbackSpec->passwordRequested;
            if (error_out)
                *error_out = strdup(volCallbackSpec->passwordRequested
                    ? "The archive header is encrypted"
                    : "No suitable archive format found");
            delete handle;
            return nullptr;
        }

        // Push the first (outermost) level
        SZArchiveLevel rootLevel;
        rootLevel.archive = firstArchive;
        rootLevel.stream = handle->fileStream;
        handle->levels.push_back(rootLevel);

        // Drill into nested archives (disk images containing filesystems)
        static const int kMaxNestingDepth = 16;
        for (int depth = 0; depth < kMaxNestingDepth; depth++) {
            IInArchive *currentArc = handle->levels.back().archive;

            // Check if this archive signals a nested container
            NWindows::NCOM::CPropVariant prop;
            currentArc->GetArchiveProperty(kpidMainSubfile, &prop);
            if (prop.vt != VT_UI4)
                break;
            UInt32 mainSubfile = prop.ulVal;

            // Validate index
            UInt32 itemCount = 0;
            currentArc->GetNumberOfItems(&itemCount);
            if (mainSubfile >= itemCount)
                break;

            // Get IInArchiveGetStream from current archive
            CMyComPtr<IInArchiveGetStream> getStream;
            if (currentArc->QueryInterface(
                    IID_IInArchiveGetStream_Local,
                    (void **)&getStream) != S_OK || !getStream)
                break;

            // Extract the sub-stream
            CMyComPtr<ISequentialInStream> subSeqStream;
            if (getStream->GetStream(mainSubfile, &subSeqStream) != S_OK
                || !subSeqStream)
                break;

            // Need seekable IInStream for archive opening
            CMyComPtr<IInStream> subStream;
            if (subSeqStream->QueryInterface(
                    IID_IInStream_Local,
                    (void **)&subStream) != S_OK || !subStream)
                break;

            // Try to open the sub-stream as a new archive
            CMyComPtr<IInArchive> innerArchive;
            if (tryOpenStream(subStream, innerArchive) != S_OK)
                break;

            // Push the new level
            SZArchiveLevel level;
            level.archive = innerArchive;
            level.stream = subStream;
            handle->levels.push_back(level);
        }

        // Entry count comes from the innermost archive
        UInt32 numItems = 0;
        handle->activeArchive()->GetNumberOfItems(&numItems);
        handle->numItems = numItems;

        // Cache IArchiveGetRawProps if the archive supports it
        handle->activeArchive()->QueryInterface(
            IID_IArchiveGetRawProps_Local,
            (void **)&handle->rawProps);

        // Check if this is a tree-based archive (disk images etc.)
        if (handle->rawProps) {
            NWindows::NCOM::CPropVariant propIsTree;
            handle->activeArchive()->GetArchiveProperty(kpidIsTree, &propIsTree);
            handle->isTree = (propIsTree.vt == VT_BOOL
                && propIsTree.boolVal != VARIANT_FALSE);
        }

        return static_cast<SZArchiveRef>(handle);
    } catch (...) {
        if (error_out)
            *error_out = strdup("Internal error during archive open");
        return nullptr;
    }
}

void sz_set_password(SZArchiveRef archive, const char *password) {
    if (!archive) return;
    auto *handle = static_cast<SZArchiveHandle *>(archive);
    if (password) {
        handle->password = password;
        handle->hasPassword = true;
    } else {
        handle->password.clear();
        handle->hasPassword = false;
    }
}

void sz_close(SZArchiveRef archive) {
    if (!archive) return;
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);
        // Close archives in reverse order (innermost first)
        for (auto it = handle->levels.rbegin();
             it != handle->levels.rend(); ++it) {
            if (it->archive)
                it->archive->Close();
        }
        delete handle;
    } catch (...) {
        // Silently swallow exceptions during cleanup
    }
}

int32_t sz_entry_count(SZArchiveRef archive) {
    if (!archive) return -1;
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);
        return static_cast<int32_t>(handle->numItems);
    } catch (...) {
        return -1;
    }
}

bool sz_get_entry(SZArchiveRef archive, uint32_t index, SZEntry *entry_out) {
    if (!archive || !entry_out) return false;
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);
        if (index >= handle->numItems) return false;

        // Skip alternate streams (macOS xattr, NTFS ADS)
        IInArchive *arc = handle->activeArchive();
        NWindows::NCOM::CPropVariant propAltStream;
        arc->GetProperty(index, kpidIsAltStream, &propAltStream);
        if (propAltStream.vt == VT_BOOL
            && propAltStream.boolVal != VARIANT_FALSE)
            return false;

        memset(entry_out, 0, sizeof(SZEntry));
        entry_out->index = index;
        entry_out->mtime = -1;
        entry_out->is_alt_stream = false;

        // Path
        NWindows::NCOM::CPropVariant propPath;
        arc->GetProperty(index, kpidPath, &propPath);
        std::string pathStr = PropVariantToUTF8(propPath);
        if (pathStr.empty()) pathStr = "unknown";  // match CExtractCallback fallback
        entry_out->path = handle->storeString(pathStr);

        // Parent index and name (tree-aware)
        if (handle->rawProps && handle->isTree) {
            // Tree-based format: get parent from IArchiveGetRawProps
            UInt32 parent = (UInt32)(Int32)-1;
            UInt32 parentType = 0;
            handle->rawProps->GetParent(index, &parent, &parentType);
            entry_out->parent_index = (parent == (UInt32)(Int32)-1)
                ? -1 : (int32_t)parent;

            // Get name via GetRawProp (faster than GetProperty)
            const void *nameData = nullptr;
            UInt32 nameSize = 0;
            UInt32 namePropType = 0;
            handle->rawProps->GetRawProp(index, kpidName,
                &nameData, &nameSize, &namePropType);
            if (nameData && nameSize > 0) {
                // Raw prop returns wchar_t* (LE) or UTF-8
                if (namePropType == NPropDataType::kUtf8z) {
                    entry_out->name = handle->storeString(
                        std::string((const char *)nameData));
                } else {
                    // wchar_t* zero-terminated little-endian
                    UString us((const wchar_t *)nameData);
                    entry_out->name = handle->storeString(UStringToUTF8(us));
                }
            } else {
                // Fallback: extract from path
                auto pos = pathStr.rfind('/');
                if (pos == std::string::npos) pos = pathStr.rfind('\\');
                entry_out->name = handle->storeString(
                    pos != std::string::npos ? pathStr.substr(pos + 1) : pathStr);
            }
        } else {
            // Non-tree format: derive name from path
            entry_out->parent_index = -1;
            auto pos = pathStr.rfind('/');
            if (pos == std::string::npos) pos = pathStr.rfind('\\');
            entry_out->name = handle->storeString(
                pos != std::string::npos ? pathStr.substr(pos + 1) : pathStr);
        }

        // Size
        NWindows::NCOM::CPropVariant propSize;
        arc->GetProperty(index, kpidSize, &propSize);
        if (propSize.vt == VT_UI8)
            entry_out->size = propSize.uhVal.QuadPart;
        else if (propSize.vt == VT_UI4)
            entry_out->size = propSize.ulVal;

        // Packed size
        NWindows::NCOM::CPropVariant propPackSize;
        arc->GetProperty(index, kpidPackSize, &propPackSize);
        if (propPackSize.vt == VT_UI8)
            entry_out->packed_size = propPackSize.uhVal.QuadPart;
        else if (propPackSize.vt == VT_UI4)
            entry_out->packed_size = propPackSize.ulVal;

        // Attributes
        NWindows::NCOM::CPropVariant propAttrib;
        arc->GetProperty(index, kpidAttrib, &propAttrib);
        if (propAttrib.vt == VT_UI4)
            entry_out->attributes = propAttrib.ulVal;

        // POSIX permissions
        NWindows::NCOM::CPropVariant propPosix;
        arc->GetProperty(index, kpidPosixAttrib, &propPosix);
        if (propPosix.vt == VT_UI4)
            entry_out->posix_permissions = propPosix.ulVal & 0xFFFF;

        // Is directory
        NWindows::NCOM::CPropVariant propIsDir;
        arc->GetProperty(index, kpidIsDir, &propIsDir);
        entry_out->is_directory =
            (propIsDir.vt == VT_BOOL && propIsDir.boolVal != VARIANT_FALSE);

        // Is encrypted
        NWindows::NCOM::CPropVariant propEncrypted;
        arc->GetProperty(index, kpidEncrypted, &propEncrypted);
        entry_out->is_encrypted =
            (propEncrypted.vt == VT_BOOL && propEncrypted.boolVal != VARIANT_FALSE);

        // Modification time
        NWindows::NCOM::CPropVariant propMTime;
        arc->GetProperty(index, kpidMTime, &propMTime);
        if (propMTime.vt == VT_FILETIME) {
            entry_out->mtime = FileTimeToUnixEpoch(propMTime.filetime);
        }

        return true;
    } catch (...) {
        return false;
    }
}

int sz_extract_entry(SZArchiveRef archive, uint32_t index,
                     const char *dest_dir, char **error_out) {
    if (!archive || !dest_dir) {
        if (error_out) *error_out = strdup("Invalid arguments");
        return -1;
    }
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);

        AString aDest(dest_dir);
        UString uDest;
        ConvertUTF8ToUnicode(aDest, uDest);
        FString fDest = us2fs(uDest);

        auto *callback = new CExtractCallback(handle->activeArchive(), fDest,
                                                handle->password, handle->hasPassword);
        CMyComPtr<IArchiveExtractCallback> callbackRef(callback);

        const UInt32 indices[1] = { index };
        HRESULT hr = handle->activeArchive()->Extract(indices, 1, 0, callback);

        return finishExtract(callback, hr, error_out);
    } catch (...) {
        if (error_out) *error_out = strdup("Internal error during extraction");
        return -1;
    }
}

int sz_extract_entries(SZArchiveRef archive, const uint32_t *indices,
                       uint32_t count, const char *dest_dir,
                       sz_progress_callback progress, void *progress_context,
                       char **error_out) {
    if (!archive || !dest_dir || (!indices && count > 0)) {
        if (error_out) *error_out = strdup("Invalid arguments");
        return SZ_EXTRACT_FAILED;
    }
    if (count == 0) return SZ_EXTRACT_OK;
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);

        AString aDest(dest_dir);
        UString uDest;
        ConvertUTF8ToUnicode(aDest, uDest);
        FString fDest = us2fs(uDest);

        auto *callback = new CExtractCallback(handle->activeArchive(), fDest,
                                                handle->password, handle->hasPassword,
                                                progress, progress_context);
        CMyComPtr<IArchiveExtractCallback> callbackRef(callback);

        HRESULT hr = handle->activeArchive()->Extract(
            indices, count, 0, callback);

        return finishExtract(callback, hr, error_out);
    } catch (...) {
        if (error_out) *error_out = strdup("Internal error during extraction");
        return SZ_EXTRACT_FAILED;
    }
}

int sz_extract_all(SZArchiveRef archive, const char *dest_dir,
                   sz_progress_callback progress, void *progress_context,
                   char **error_out) {
    if (!archive || !dest_dir) {
        if (error_out) *error_out = strdup("Invalid arguments");
        return SZ_EXTRACT_FAILED;
    }
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);

        AString aDest(dest_dir);
        UString uDest;
        ConvertUTF8ToUnicode(aDest, uDest);
        FString fDest = us2fs(uDest);

        auto *callback = new CExtractCallback(handle->activeArchive(), fDest,
                                                handle->password, handle->hasPassword,
                                                progress, progress_context);
        CMyComPtr<IArchiveExtractCallback> callbackRef(callback);

        HRESULT hr = handle->activeArchive()->Extract(
            nullptr, (UInt32)(Int32)-1, 0, callback);

        return finishExtract(callback, hr, error_out);
    } catch (...) {
        if (error_out) *error_out = strdup("Internal error during extraction");
        return SZ_EXTRACT_FAILED;
    }
}

bool sz_is_tree(SZArchiveRef archive) {
    if (!archive) return false;
    try {
        auto *handle = static_cast<SZArchiveHandle *>(archive);
        return handle->isTree;
    } catch (...) {
        return false;
    }
}

const char* sz_version(void) {
    return MY_VERSION;
}

} // extern "C"

