// sevenzip_bridge_write.cpp -- C bridge for creating/updating 7-zip archives.
// All C++ exceptions are caught at the extern "C" boundary.

#include "StdAfx.h"

#include "include/sevenzip_bridge.h"

#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>
#include <climits>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <strings.h>
#include <algorithm>
#include <cstdio>

#include "Common/MyWindows.h"
#include "Common/MyCom.h"
#include "Common/MyString.h"
#include "Common/StringConvert.h"
#include "Common/UTFConvert.h"

#include "Windows/FileDir.h"
#include "Windows/FileFind.h"
#include "Windows/PropVariant.h"
#include "Windows/TimeUtils.h"

#include "7zip/Common/FileStreams.h"
#include "7zip/Common/StreamObjects.h"

#include "7zip/Archive/IArchive.h"
#include "7zip/IPassword.h"

// Defined in sevenzip_bridge.cpp -- forces 7-Zip's narrow<->wide path
// conversions to UTF-8 so archives with non-ASCII names work on macOS.
void sz_force_utf8_paths(void);

// --- GUIDs ---

static const GUID IID_IOutArchive_Local = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x06, 0x00, 0xA0, 0x00, 0x00}
};

static const GUID IID_ISetProperties_Local = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x06, 0x00, 0x03, 0x00, 0x00}
};

static const GUID IID_IInArchive_Local_W = {
  0x23170F69, 0x40C1, 0x278A,
  {0x00, 0x00, 0x00, 0x06, 0x00, 0x60, 0x00, 0x00}
};

// --- External functions ---
STDAPI GetNumberOfFormats(UINT32 *numFormats);
STDAPI GetHandlerProperty2(UInt32 formatIndex, PROPID propID, PROPVARIANT *value);
STDAPI CreateArchiver(const GUID *clsid, const GUID *iid, void **outObject);

// --- Helpers ---

static char* makeCError(const std::string &msg) {
    char *buf = (char *)malloc(msg.size() + 1);
    if (buf) memcpy(buf, msg.c_str(), msg.size() + 1);
    return buf;
}

static UString UTF8ToUString(const char *utf8) {
    UString result;
    AString a(utf8);
    ConvertUTF8ToUnicode(a, result);
    return result;
}

// Effective posix mode of an update item: the explicit value, or the on-disk
// mode for ADD_FILE items, or 0 when unknown.
static UInt32 EffectivePosixMode(const SZUpdateItem &item) {
    if (item.posix_permissions != 0)
        return (UInt32)item.posix_permissions;
    if (item.op == SZ_UPDATE_ADD_FILE && item.disk_path) {
        struct stat st;
        // lstat, not stat: a symbolic link has to reach the archive as a link.
        // Following it here would store S_IFREG plus a copy of whatever it points
        // at -- and inside a framework or an .app, the version symlinks are what
        // hold the bundle together.
        if (lstat(item.disk_path, &st) == 0)
            return (UInt32)(st.st_mode & 0xFFFF);
    }
    return 0;
}

/// The target of `path` when it is a symbolic link; empty for anything else.
///
/// 7-Zip stores a symlink as an entry whose *contents* are the target path, with
/// S_IFLNK set in the POSIX mode -- the same shape the extraction side turns back
/// into a real link. So a link needs both its size and its stream to come from
/// here rather than from the file it points at.
static std::string ReadLinkTarget(const char *path) {
    if (!path)
        return std::string();

    struct stat st;
    if (lstat(path, &st) != 0 || !S_ISLNK(st.st_mode))
        return std::string();

    // st_size is the target length on every filesystem that bothers to fill it
    // in, but not all do, so ask for a full path's worth and trust readlink's
    // return value instead.
    char buffer[PATH_MAX];
    const ssize_t length = readlink(path, buffer, sizeof(buffer));
    if (length <= 0)
        return std::string();

    return std::string(buffer, (size_t)length);
}

/// The output split into volumes of a fixed size -- `base.001`, `base.002`, ...
/// -- the way 7-Zip's own `-v` writes them. The format handlers seek: 7z writes
/// its start header last, at offset 0, and zip goes back to finish a local
/// header. So this is a real IOutStream over the whole set, where a position
/// maps to (position / volume size, position % volume size). One volume is open
/// at a time and reopened when a seek lands in it again, so a set of hundreds
/// of volumes never runs out of file descriptors.
Z7_CLASS_IMP_COM_1(
  COutVolumeStream
  , IOutStream
)
  Z7_IFACE_COM7_IMP(ISequentialOutStream)

  std::string _base;
  UInt64 _volumeSize;
  UInt64 _position = 0;
  UInt64 _length = 0;
  int _fd = -1;
  size_t _openIndex = 0;
  std::vector<bool> _created;

  int volume(size_t index);

public:
  std::string errorMessage;

  COutVolumeStream(const char *base, UInt64 volumeSize)
    : _base(base), _volumeSize(volumeSize) {}
  ~COutVolumeStream() { if (_fd >= 0) close(_fd); }

  std::string path(size_t index) const {
      char suffix[24];
      snprintf(suffix, sizeof(suffix), ".%03zu", index + 1);
      return _base + suffix;
  }

  /// For a write that failed: nothing half-written stays behind.
  void removeAll() {
      if (_fd >= 0) { close(_fd); _fd = -1; }
      for (size_t i = 0; i < _created.size(); i++)
          if (_created[i]) unlink(path(i).c_str());
  }
};

int COutVolumeStream::volume(size_t index) {
    if (_fd >= 0 && _openIndex == index)
        return _fd;
    if (_fd >= 0) { close(_fd); _fd = -1; }
    if (_created.size() <= index)
        _created.resize(index + 1, false);
    // Truncated when first made, reopened as is after that: a seek back into a
    // finished volume must not throw away what it already holds.
    const int flags = O_RDWR | O_CREAT | (_created[index] ? 0 : O_TRUNC);
    _fd = open(path(index).c_str(), flags, 0644);
    if (_fd < 0) {
        // Worded like the single-file case, which the app answers by asking for
        // access to the folder: volumes are siblings of the file the save panel
        // granted, never that file itself.
        errorMessage = "Cannot create output file: " + path(index);
        return -1;
    }
    _created[index] = true;
    _openIndex = index;
    return _fd;
}

Z7_COM7F_IMF(COutVolumeStream::Write(const void *data, UInt32 size, UInt32 *processedSize))
{
    if (processedSize) *processedSize = 0;
    const Byte *bytes = (const Byte *)data;
    while (size > 0) {
        const size_t index = (size_t)(_position / _volumeSize);
        const UInt64 offset = _position % _volumeSize;
        const UInt32 chunk = (UInt32)std::min<UInt64>(size, _volumeSize - offset);
        const int fd = volume(index);
        if (fd < 0) return E_FAIL;
        const ssize_t written = pwrite(fd, bytes, chunk, (off_t)offset);
        if (written <= 0) {
            errorMessage = "Cannot write output file: " + path(index);
            return E_FAIL;
        }
        bytes += written;
        size -= (UInt32)written;
        _position += (UInt64)written;
        if (_position > _length) _length = _position;
        if (processedSize) *processedSize += (UInt32)written;
    }
    return S_OK;
}

Z7_COM7F_IMF(COutVolumeStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition))
{
    Int64 base;
    switch (seekOrigin) {
        case STREAM_SEEK_SET: base = 0; break;
        case STREAM_SEEK_CUR: base = (Int64)_position; break;
        case STREAM_SEEK_END: base = (Int64)_length; break;
        default: return E_INVALIDARG;
    }
    if (base + offset < 0)
        return E_INVALIDARG;
    _position = (UInt64)(base + offset);
    if (newPosition) *newPosition = _position;
    return S_OK;
}

Z7_COM7F_IMF(COutVolumeStream::SetSize(UInt64 newSize))
{
    // Volumes past the new end go; the last one left is cut to size.
    const size_t keep = newSize == 0 ? 0 : (size_t)((newSize - 1) / _volumeSize) + 1;
    if (_fd >= 0 && _openIndex >= keep) { close(_fd); _fd = -1; }
    for (size_t i = keep; i < _created.size(); i++)
        if (_created[i]) { unlink(path(i).c_str()); _created[i] = false; }
    if (keep > 0) {
        const int fd = volume(keep - 1);
        if (fd < 0) return E_FAIL;
        if (ftruncate(fd, (off_t)(newSize - (UInt64)(keep - 1) * _volumeSize)) != 0)
            return E_FAIL;
    }
    _length = newSize;
    return S_OK;
}

static FILETIME UnixEpochToFileTime(int64_t unixTime) {
    FILETIME ft;
    if (unixTime < 0) {
        ft.dwLowDateTime = 0;
        ft.dwHighDateTime = 0;
    } else {
        UInt64 ticks = ((UInt64)unixTime + 11644473600ULL) * 10000000ULL;
        ft.dwLowDateTime = (DWORD)(ticks & 0xFFFFFFFF);
        ft.dwHighDateTime = (DWORD)(ticks >> 32);
    }
    return ft;
}

// --- Find format by name and get CLSID ---

static bool FindFormatByName(const char *formatName, GUID &clsid, bool requireUpdate) {
    UInt32 numFormats = 0;
    GetNumberOfFormats(&numFormats);

    UString target = UTF8ToUString(formatName);
    target.MakeLower_Ascii();

    for (UInt32 i = 0; i < numFormats; i++) {
        NWindows::NCOM::CPropVariant propName;
        GetHandlerProperty2(i, NArchive::NHandlerPropID::kName, &propName);
        if (propName.vt != VT_BSTR || !propName.bstrVal) continue;

        UString name(propName.bstrVal);
        name.MakeLower_Ascii();
        if (name != target) continue;

        if (requireUpdate) {
            NWindows::NCOM::CPropVariant propUpdate;
            GetHandlerProperty2(i, NArchive::NHandlerPropID::kUpdate, &propUpdate);
            if (propUpdate.vt != VT_BOOL || propUpdate.boolVal == VARIANT_FALSE) continue;
        }

        NWindows::NCOM::CPropVariant propClassID;
        GetHandlerProperty2(i, NArchive::NHandlerPropID::kClassID, &propClassID);
        if (propClassID.vt != VT_BSTR || !propClassID.bstrVal) continue;

        memcpy(&clsid, propClassID.bstrVal, sizeof(GUID));
        return true;
    }
    return false;
}

// --- Update callback ---

class CUpdateCallback final :
    public IArchiveUpdateCallback,
    public ICryptoGetTextPassword2,
    public CMyUnknownImp
{
    Z7_COM_UNKNOWN_IMP_2(IArchiveUpdateCallback, ICryptoGetTextPassword2)

public:
    const SZUpdateItem *items;
    UInt32 itemCount;
    std::string errorMessage;
    /// What new entries are encrypted with; empty for none.
    std::string encryptionPassword;

    // Progress forwarding (optional). aborted is set when the callback
    // asks to stop, so UpdateItems bails out with E_ABORT.
    sz_progress_callback progressCallback = nullptr;
    void *progressContext = nullptr;
    UInt64 progressTotal = 0;
    bool aborted = false;
    /// Backing store for the symlink targets handed to 7-Zip as entry contents.
    /// A deque because CBufInStream keeps a pointer into what it is given, and a
    /// deque never relocates the elements already in it.
    std::deque<std::string> linkTargets;

    CUpdateCallback(const SZUpdateItem *items_, UInt32 count)
        : items(items_), itemCount(count) {}

    // IProgress
    Z7_COM7F_IMF(SetTotal(UInt64 total)) {
        progressTotal = total;
        if (progressCallback && !progressCallback(0, total, progressContext)) {
            aborted = true;
            return E_ABORT;
        }
        return S_OK;
    }
    Z7_COM7F_IMF(SetCompleted(const UInt64 *completeValue)) {
        if (progressCallback && completeValue) {
            if (!progressCallback(*completeValue, progressTotal, progressContext)) {
                aborted = true;
                return E_ABORT;
            }
        }
        return S_OK;
    }

    // IArchiveUpdateCallback
    Z7_COM7F_IMF(GetUpdateItemInfo(UInt32 index,
        Int32 *newData, Int32 *newProps, UInt32 *indexInArchive));
    Z7_COM7F_IMF(GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value));
    Z7_COM7F_IMF(GetStream(UInt32 index, ISequentialInStream **inStream));
    Z7_COM7F_IMF(SetOperationResult(Int32)) { return S_OK; }

    // ICryptoGetTextPassword2
    Z7_COM7F_IMF(CryptoGetTextPassword2(Int32 *passwordIsDefined, BSTR *password));
};

Z7_COM7F_IMF(CUpdateCallback::GetUpdateItemInfo(UInt32 index,
    Int32 *newData, Int32 *newProps, UInt32 *indexInArchive))
{
    if (index >= itemCount) return E_INVALIDARG;
    const SZUpdateItem &item = items[index];
    switch (item.op) {
        case SZ_UPDATE_KEEP:
            if (newData) *newData = 0;
            if (newProps) *newProps = 0;
            if (indexInArchive) *indexInArchive = item.source_index;
            break;
        case SZ_UPDATE_MOVE:
            if (newData) *newData = 0;
            if (newProps) *newProps = 1;
            if (indexInArchive) *indexInArchive = item.source_index;
            break;
        case SZ_UPDATE_ADD_FILE:
        case SZ_UPDATE_ADD_DATA:
        case SZ_UPDATE_ADD_DIR:
            if (newData) *newData = 1;
            if (newProps) *newProps = 1;
            if (indexInArchive) *indexInArchive = (UInt32)(Int32)-1;
            break;
    }
    return S_OK;
}

Z7_COM7F_IMF(CUpdateCallback::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value))
{
    if (index >= itemCount) return E_INVALIDARG;
    const SZUpdateItem &item = items[index];
    NWindows::NCOM::CPropVariant prop;

    if (propID == kpidIsAnti) {
        prop = false;
        prop.Detach(value);
        return S_OK;
    }

    switch (propID) {
        case kpidPath: {
            if (item.archive_path)
                prop = UTF8ToUString(item.archive_path);
            break;
        }
        case kpidIsDir:
            prop = item.is_directory;
            break;
        case kpidSize: {
            if (item.op == SZ_UPDATE_ADD_DATA) {
                prop = (UInt64)item.data_size;
            } else if (item.op == SZ_UPDATE_ADD_FILE && !item.is_directory) {
                // A symlink's content is its target path, so that is its size
                // too -- lstat's st_size agrees, but readlink is the one that
                // GetStream will hand over, so measure the same thing twice.
                const std::string link = ReadLinkTarget(item.disk_path);
                struct stat st;
                if (!link.empty())
                    prop = (UInt64)link.size();
                else if (item.disk_path && stat(item.disk_path, &st) == 0)
                    prop = (UInt64)st.st_size;
                else
                    prop = (UInt64)0;
            } else {
                prop = (UInt64)0;
            }
            break;
        }
        case kpidMTime: {
            if (item.mtime >= 0) {
                FILETIME ft = UnixEpochToFileTime(item.mtime);
                prop = ft;
            } else if ((item.op == SZ_UPDATE_ADD_FILE || item.op == SZ_UPDATE_ADD_DIR)
                       && item.disk_path) {
                // Directories as well as files: a folder entry carries no contents
                // but it does carry a date, and leaving it unset stores the zip
                // epoch, so every folder in the archive extracts stamped 1980.
                struct stat st;
                // lstat for the same reason as the mode: a link's own time, not
                // the time of whatever it points at.
                if (lstat(item.disk_path, &st) == 0) {
                    FILETIME ft = UnixEpochToFileTime(st.st_mtime);
                    prop = ft;
                }
            }
            break;
        }
        case kpidAttrib: {
            UInt32 attr = 0;
            if (item.is_directory)
                attr = 0x10; // FILE_ATTRIBUTE_DIRECTORY
            // The zip writer only reads kpidAttrib. Posix mode travels in the
            // high 16 bits, flagged by FILE_ATTRIBUTE_UNIX_EXTENSION (7-Zip
            // convention) — without it new entries extract with mode 000.
            UInt32 posix = EffectivePosixMode(item);
            if (posix != 0)
                attr |= 0x8000u | (posix << 16);
            prop = attr;
            break;
        }
        case kpidPosixAttrib: {
            UInt32 posix = EffectivePosixMode(item);
            if (posix != 0)
                prop = posix;
            break;
        }
    }
    prop.Detach(value);
    return S_OK;
}

Z7_COM7F_IMF(CUpdateCallback::GetStream(UInt32 index, ISequentialInStream **inStream))
{
    if (index >= itemCount) return E_INVALIDARG;
    *inStream = nullptr;

    const SZUpdateItem &item = items[index];

    if (item.is_directory || item.op == SZ_UPDATE_KEEP || item.op == SZ_UPDATE_MOVE)
        return S_OK;

    if (item.op == SZ_UPDATE_ADD_FILE) {
        if (!item.disk_path) {
            errorMessage = "Missing disk path for ADD_FILE item";
            return E_FAIL;
        }

        // A symbolic link is stored as its target path, not as the bytes of the
        // file it points at. The string has to outlive this call -- CBufInStream
        // holds the buffer rather than copying it -- and a deque never moves what
        // it already holds, so earlier entries stay valid as later ones arrive.
        const std::string link = ReadLinkTarget(item.disk_path);
        if (!link.empty()) {
            linkTargets.push_back(link);
            const std::string &stored = linkTargets.back();
            CBufInStream *bufStream = new CBufInStream;
            CMyComPtr<ISequentialInStream> streamLoc(bufStream);
            bufStream->Init((const Byte *)stored.data(), stored.size());
            *inStream = streamLoc.Detach();
            return S_OK;
        }

        CInFileStream *fileStream = new CInFileStream;
        CMyComPtr<ISequentialInStream> streamLoc(fileStream);
        FString fpath = us2fs(UTF8ToUString(item.disk_path));
        if (!fileStream->Open(fpath)) {
            errorMessage = "Cannot open file: ";
            errorMessage += item.disk_path;
            return E_FAIL;
        }
        *inStream = streamLoc.Detach();
        return S_OK;
    }

    if (item.op == SZ_UPDATE_ADD_DATA) {
        CBufInStream *bufStream = new CBufInStream;
        CMyComPtr<ISequentialInStream> streamLoc(bufStream);
        bufStream->Init((const Byte *)item.data, (size_t)item.data_size);
        *inStream = streamLoc.Detach();
        return S_OK;
    }

    return S_OK;
}

Z7_COM7F_IMF(CUpdateCallback::CryptoGetTextPassword2(Int32 *passwordIsDefined, BSTR *password))
{
    *password = nullptr;
    *passwordIsDefined = encryptionPassword.empty() ? 0 : 1;
    if (encryptionPassword.empty())
        return S_OK;
    UString u = UTF8ToUString(encryptionPassword.c_str());
    *password = ::SysAllocString((const OLECHAR *)(const wchar_t *)u);
    return *password ? S_OK : E_OUTOFMEMORY;
}

// --- Main entry point ---

extern "C"
int sz_update_archive(
    const char *source_path,
    const char *dest_path,
    const SZUpdateItem *items,
    uint32_t item_count,
    const SZCompressionOptions *options,
    sz_progress_callback progress,
    void *progress_context,
    char **error_out)
{
    if (error_out) *error_out = nullptr;

    try {
        // macOS paths are UTF-8; make 7-Zip honor that (see sz_force_utf8_paths).
        sz_force_utf8_paths();

        // 1. Find the format
        GUID clsid;
        const char *fmt = (options && options->format) ? options->format : "7z";
        if (!FindFormatByName(fmt, clsid, true)) {
            if (error_out) *error_out = makeCError(
                std::string("Unsupported or non-writable format: ") + fmt);
            return 1;
        }

        // 2. Open source archive if editing, and obtain IOutArchive
        CMyComPtr<IInArchive> inArchive;
        CMyComPtr<IInStream> inFileStream;
        CMyComPtr<IOutArchive> outArchive;

        if (source_path) {
            // For editing, auto-detect the source format (try all handlers),
            // then QI the successful handler for IOutArchive.
            CInFileStream *fs = new CInFileStream;
            inFileStream = fs;
            FString fpath = us2fs(UTF8ToUString(source_path));
            if (!fs->Open(fpath)) {
                if (error_out) *error_out = makeCError(
                    std::string("Cannot open source archive: ") + source_path);
                return 1;
            }

            UInt32 numFormats = 0;
            GetNumberOfFormats(&numFormats);
            bool opened = false;
            for (UInt32 i = 0; i < numFormats; i++) {
                NWindows::NCOM::CPropVariant propClassID;
                GetHandlerProperty2(i, NArchive::NHandlerPropID::kClassID, &propClassID);
                if (propClassID.vt != VT_BSTR || !propClassID.bstrVal) continue;

                GUID fmtClsid;
                memcpy(&fmtClsid, propClassID.bstrVal, sizeof(GUID));

                CMyComPtr<IInArchive> candidate;
                HRESULT hr = CreateArchiver(&fmtClsid, &IID_IInArchive_Local_W, (void **)&candidate);
                if (hr != S_OK || !candidate) continue;

                UInt64 newPos;
                inFileStream->Seek(0, STREAM_SEEK_SET, &newPos);
                UInt64 maxCheck = 1 << 22;
                hr = candidate->Open(inFileStream, &maxCheck, nullptr);
                if (hr == S_OK) {
                    inArchive = candidate;
                    opened = true;
                    break;
                }
                candidate->Close();
            }
            if (!opened) {
                if (error_out) *error_out = makeCError(
                    std::string("Failed to open source archive (no format matched): ") + source_path);
                return 1;
            }

            // QI the detected handler for IOutArchive
            HRESULT hr = inArchive->QueryInterface(IID_IOutArchive_Local, (void **)&outArchive);
            if (hr != S_OK || !outArchive) {
                if (error_out) *error_out = makeCError("Source archive format does not support writing");
                return 1;
            }
        } else {
            // 3. Create a fresh output archive handler
            HRESULT hr = CreateArchiver(&clsid, &IID_IOutArchive_Local, (void **)&outArchive);
            if (hr != S_OK || !outArchive) {
                if (error_out) *error_out = makeCError("Failed to create output archive handler");
                return 1;
            }
        }

        // 4. Set compression properties
        if (options) {
            CMyComPtr<ISetProperties> setProps;
            outArchive->QueryInterface(IID_ISetProperties_Local, (void **)&setProps);
            if (setProps) {
                std::vector<const wchar_t *> names;
                std::vector<NWindows::NCOM::CPropVariant> values;
                auto addUInt = [&](const wchar_t *name, UInt32 v) {
                    NWindows::NCOM::CPropVariant prop; prop = v;
                    names.push_back(name); values.push_back(prop);
                };
                auto addBool = [&](const wchar_t *name, bool v) {
                    NWindows::NCOM::CPropVariant prop; prop = v;
                    names.push_back(name); values.push_back(prop);
                };
                auto addString = [&](const wchar_t *name, const char *v) {
                    NWindows::NCOM::CPropVariant prop; prop = UTF8ToUString(v);
                    names.push_back(name); values.push_back(prop);
                };
                const bool isZip = options->format && strcasecmp(options->format, "zip") == 0;

                addUInt(L"x", options->level);
                if (options->method)
                    addString(L"0", options->method);

                // PPMd calls its dictionary the model's memory and its word size
                // the model's order; every other method says "d" and "fb".
                const bool ppmd = options->method && strcasecmp(options->method, "ppmd") == 0;
                // In bytes, as a string: a bare number is read as a power of two
                // ("d=24" is 16 MB), which would refuse 65536 as out of range.
                if (options->dictionary_size > 0) {
                    char spec[32];
                    snprintf(spec, sizeof(spec), "%llub", (unsigned long long)options->dictionary_size);
                    addString(ppmd ? L"mem" : L"d", spec);
                }
                if (options->word_size > 0)
                    addUInt(ppmd ? L"o" : L"fb", options->word_size);

                if (options->solid_block_size == UINT64_MAX) {
                    addBool(L"s", true);
                } else if (options->solid_block_size > 0) {
                    char spec[32];
                    snprintf(spec, sizeof(spec), "%llub", (unsigned long long)options->solid_block_size);
                    addString(L"s", spec);
                } else if (options->solid_mode >= 0) {
                    addBool(L"s", options->solid_mode != 0);
                }

                // The password itself comes through CryptoGetTextPassword2.
                const bool encrypts = options->password && options->password[0] != 0;
                if (encrypts && isZip)
                    addString(L"em", options->encryption_method ? options->encryption_method : "AES256");
                if (encrypts && !isZip && options->encrypt_names)
                    addBool(L"he", true);

                // A setting the handler refuses must not be dropped silently: the
                // archive would come out other than the one asked for.
                if (setProps->SetProperties(names.data(), values.data(), (UInt32)names.size()) != S_OK) {
                    if (error_out) *error_out = makeCError(
                        "7-Zip does not accept these settings for this format and method");
                    return 1;
                }
            }
        }

        // 5. Create the output: one file, or a set of volumes
        CMyComPtr<ISequentialOutStream> outStreamLoc;
        COutVolumeStream *volumes = nullptr;
        if (options && options->volume_size > 0) {
            volumes = new COutVolumeStream(dest_path, options->volume_size);
            outStreamLoc = volumes;
        } else {
            COutFileStream *outFileStream = new COutFileStream;
            outStreamLoc = outFileStream;
            FString destFPath = us2fs(UTF8ToUString(dest_path));
            if (!outFileStream->Create_ALWAYS(destFPath)) {
                if (error_out) *error_out = makeCError(
                    std::string("Cannot create output file: ") + dest_path);
                return 1;
            }
        }

        // 6. Create callback and run update
        CUpdateCallback *callbackSpec = new CUpdateCallback(items, item_count);
        callbackSpec->progressCallback = progress;
        callbackSpec->progressContext = progress_context;
        if (options && options->password)
            callbackSpec->encryptionPassword = options->password;
        CMyComPtr<IArchiveUpdateCallback> callback(callbackSpec);

        HRESULT hr = outArchive->UpdateItems(outStreamLoc, item_count, callback);
        if (hr != S_OK) {
            // Nothing half-written stays behind under the name that was picked.
            std::string volumeError = volumes ? volumes->errorMessage : std::string();
            if (volumes) {
                volumes->removeAll();
            } else {
                outStreamLoc.Release();
                unlink(dest_path);
            }
            if (!volumeError.empty()) {
                if (error_out) *error_out = makeCError(volumeError);
                return 1;
            }
            if (callbackSpec->aborted) {
                if (error_out) *error_out = makeCError("Aborted by progress callback");
                return 2;
            }
            std::string msg = "UpdateItems failed";
            if (!callbackSpec->errorMessage.empty())
                msg += ": " + callbackSpec->errorMessage;
            if (error_out) *error_out = makeCError(msg);
            return 1;
        }

        // 7. Close source archive
        if (inArchive)
            inArchive->Close();

        return 0;
    } catch (const std::exception &e) {
        if (error_out) *error_out = makeCError(
            std::string("Exception: ") + e.what());
        return 1;
    } catch (...) {
        if (error_out) *error_out = makeCError("Unknown exception");
        return 1;
    }
}
