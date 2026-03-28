// sevenzip_bridge.cpp -- C bridge between 7-zip C++ internals and Swift.
// All C++ exceptions are caught at the extern "C" boundary.

#include "StdAfx.h"

#include "include/sevenzip_bridge.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <sys/stat.h>

#include "Common/MyWindows.h"
#include "Common/MyCom.h"
#include "Common/MyString.h"
#include "Common/StringConvert.h"
#include "Common/UTFConvert.h"
#include "Common/IntToString.h"

#include "Windows/FileDir.h"
#include "Windows/FileFind.h"
#include "Windows/FileName.h"
#include "Windows/PropVariant.h"
#include "Windows/PropVariantConv.h"

#include "7zip/Common/FileStreams.h"
#include "7zip/Common/StreamUtils.h"

#include "7zip/Archive/IArchive.h"
#include "7zip/IPassword.h"

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

// --- External functions from ArchiveExports.cpp / CodecExports.cpp ---
STDAPI GetNumberOfFormats(UINT32 *numFormats);
STDAPI GetHandlerProperty2(UInt32 formatIndex, PROPID propID, PROPVARIANT *value);
STDAPI CreateArchiver(const GUID *clsid, const GUID *iid, void **outObject);

// --- Helpers ---

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
    std::vector<std::string> storedStrings;
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

// --- Format probing helper ---

/// Try all registered formats against the given seekable stream.
/// Returns S_OK on success with archiveOut set, S_FALSE if no format matched.
static HRESULT tryOpenStream(
    IInStream *stream,
    CMyComPtr<IInArchive> &archiveOut)
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
        hr = archive->Open(stream, &maxCheckStart, nullptr);
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
                     const std::string &password, bool hasPassword)
        : _archive(archive), _destDir(destDir), _outFileStream(nullptr),
          _password(password), _hasPassword(hasPassword) {}

    // IProgress
    Z7_COM7F_IMF(SetTotal(UInt64 /* total */)) { return S_OK; }
    Z7_COM7F_IMF(SetCompleted(const UInt64 * /* completeValue */)) { return S_OK; }

    // IArchiveExtractCallback
    Z7_COM7F_IMF(GetStream(UInt32 index, ISequentialOutStream **outStream, Int32 askExtractMode));
    Z7_COM7F_IMF(PrepareOperation(Int32 /* askExtractMode */)) { return S_OK; }
    Z7_COM7F_IMF(SetOperationResult(Int32 /* opRes */)) { return S_OK; }

    // ICryptoGetTextPassword
    Z7_COM7F_IMF(CryptoGetTextPassword(BSTR *password));

    std::string errorMessage;

private:
    IInArchive *_archive;
    FString _destDir;
    CMyComPtr<ISequentialOutStream> _outFileStream;
    FString _currentFilePath;
    std::string _password;
    bool _hasPassword;
};

Z7_COM7F_IMF(CExtractCallback::GetStream(
    UInt32 index, ISequentialOutStream **outStream, Int32 askExtractMode))
{
    *outStream = nullptr;
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

    FString fullPath = _destDir;
    fullPath += FCHAR_PATH_SEPARATOR;
    fullPath += us2fs(filePath);

    if (isDir) {
        NWindows::NFile::NDir::CreateComplexDir(fullPath);
        return S_OK;
    }

    // Create parent directory
    int slashPos = (int)fullPath.ReverseFind_PathSepar();
    if (slashPos >= 0) {
        FString parentDir = fullPath.Left((unsigned)slashPos);
        NWindows::NFile::NDir::CreateComplexDir(parentDir);
    }

    auto *outFileStreamSpec = new COutFileStream;
    CMyComPtr<ISequentialOutStream> outStreamRef(outFileStreamSpec);

    if (!outFileStreamSpec->Create_ALWAYS(fullPath)) {
        errorMessage = "Failed to create output file";
        return E_FAIL;
    }

    _outFileStream = outStreamRef;
    *outStream = outStreamRef.Detach();
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

// --- Bridge Implementation ---

extern "C" {

SZArchiveRef sz_open(const char *path, char **error_out) {
    try {
        auto *handle = new SZArchiveHandle();

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

        // Try each registered format on the file stream
        CMyComPtr<IInArchive> firstArchive;
        HRESULT hr = tryOpenStream(handle->fileStream, firstArchive);
        if (hr != S_OK || !firstArchive) {
            if (error_out)
                *error_out = strdup("No suitable archive format found");
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

        memset(entry_out, 0, sizeof(SZEntry));
        entry_out->index = index;
        entry_out->mtime = -1;

        IInArchive *arc = handle->activeArchive();

        // Path
        NWindows::NCOM::CPropVariant propPath;
        arc->GetProperty(index, kpidPath, &propPath);
        std::string pathStr = PropVariantToUTF8(propPath);
        entry_out->path = handle->storeString(pathStr);

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

        if (hr != S_OK || !callback->errorMessage.empty()) {
            if (error_out) {
                std::string msg = callback->errorMessage.empty()
                    ? "Extraction failed" : callback->errorMessage;
                *error_out = strdup(msg.c_str());
            }
            return -1;
        }
        return 0;
    } catch (...) {
        if (error_out) *error_out = strdup("Internal error during extraction");
        return -1;
    }
}

int sz_extract_all(SZArchiveRef archive, const char *dest_dir,
                   char **error_out) {
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

        HRESULT hr = handle->activeArchive()->Extract(
            nullptr, (UInt32)(Int32)-1, 0, callback);

        if (hr != S_OK || !callback->errorMessage.empty()) {
            if (error_out) {
                std::string msg = callback->errorMessage.empty()
                    ? "Extraction failed" : callback->errorMessage;
                *error_out = strdup(msg.c_str());
            }
            return -1;
        }
        return 0;
    } catch (...) {
        if (error_out) *error_out = strdup("Internal error during extraction");
        return -1;
    }
}

const char* sz_version(void) {
    return "Swift7zip bridge";
}

} // extern "C"
