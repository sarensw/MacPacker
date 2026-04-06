// sevenzip_bridge_write.cpp -- C bridge for creating/updating 7-zip archives.
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

#include "Windows/FileDir.h"
#include "Windows/FileFind.h"
#include "Windows/PropVariant.h"
#include "Windows/TimeUtils.h"

#include "7zip/Common/FileStreams.h"
#include "7zip/Common/StreamObjects.h"

#include "7zip/Archive/IArchive.h"
#include "7zip/IPassword.h"

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

    CUpdateCallback(const SZUpdateItem *items_, UInt32 count)
        : items(items_), itemCount(count) {}

    // IProgress
    Z7_COM7F_IMF(SetTotal(UInt64)) { return S_OK; }
    Z7_COM7F_IMF(SetCompleted(const UInt64 *)) { return S_OK; }

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
                struct stat st;
                if (item.disk_path && stat(item.disk_path, &st) == 0)
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
            } else if (item.op == SZ_UPDATE_ADD_FILE && item.disk_path) {
                struct stat st;
                if (stat(item.disk_path, &st) == 0) {
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
            prop = attr;
            break;
        }
        case kpidPosixAttrib: {
            if (item.posix_permissions != 0) {
                prop = (UInt32)item.posix_permissions;
            } else if (item.op == SZ_UPDATE_ADD_FILE && item.disk_path) {
                struct stat st;
                if (stat(item.disk_path, &st) == 0)
                    prop = (UInt32)(st.st_mode & 0xFFFF);
            }
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
    *passwordIsDefined = 0;
    *password = nullptr;
    return S_OK;
}

// --- Main entry point ---

extern "C"
int sz_update_archive(
    const char *source_path,
    const char *dest_path,
    const SZUpdateItem *items,
    uint32_t item_count,
    const SZCompressionOptions *options,
    char **error_out)
{
    if (error_out) *error_out = nullptr;

    try {
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

                // Compression level
                UString levelName(L"x");
                names.push_back(levelName);
                NWindows::NCOM::CPropVariant levelVal;
                levelVal = (UInt32)options->level;
                values.push_back(levelVal);

                // Method
                UString methodName;
                if (options->method) {
                    methodName = L"0";
                    names.push_back(methodName);
                    UString methodVal = UTF8ToUString(options->method);
                    NWindows::NCOM::CPropVariant mv;
                    mv = methodVal;
                    values.push_back(mv);
                }

                // Solid mode
                UString solidName;
                if (options->solid_mode >= 0) {
                    solidName = L"s";
                    names.push_back(solidName);
                    NWindows::NCOM::CPropVariant sv;
                    sv = (bool)(options->solid_mode != 0);
                    values.push_back(sv);
                }

                setProps->SetProperties(names.data(), values.data(), (UInt32)names.size());
            }
        }

        // 5. Create output file stream
        COutFileStream *outFileStream = new COutFileStream;
        CMyComPtr<ISequentialOutStream> outStreamLoc(outFileStream);
        FString destFPath = us2fs(UTF8ToUString(dest_path));
        if (!outFileStream->Create_ALWAYS(destFPath)) {
            if (error_out) *error_out = makeCError(
                std::string("Cannot create output file: ") + dest_path);
            return 1;
        }

        // 6. Create callback and run update
        CUpdateCallback *callbackSpec = new CUpdateCallback(items, item_count);
        CMyComPtr<IArchiveUpdateCallback> callback(callbackSpec);

        HRESULT hr = outArchive->UpdateItems(outStreamLoc, item_count, callback);
        if (hr != S_OK) {
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
