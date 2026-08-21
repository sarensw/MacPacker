#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque archive handle.
// Not thread-safe -- must only be used from the thread that called sz_open().
typedef void* SZArchiveRef;

// --- Lifecycle ---

/// Open an archive at the given filesystem path.
///
/// @param password  Password to use while reading the archive headers, or NULL.
///                  Formats that encrypt their header (7z -mhe=on, RAR -hp)
///                  cannot be listed without it. Also pre-sets the extraction
///                  password, so sz_set_password() is not needed afterwards.
/// @param needs_password_out  If non-NULL, set to true when a handler asked for
///                  a password during the open. Meaningful only on failure:
///                  it tells the caller to prompt and retry rather than report
///                  an unsupported file.
/// Returns NULL on failure. On failure, *error_out (if non-NULL) is set to a
/// malloc'd UTF-8 error string -- caller must free() it.
SZArchiveRef sz_open(const char *path, const char *password,
                     bool *needs_password_out, char **error_out);

/// Release all resources. Must be called exactly once per successful sz_open().
void sz_close(SZArchiveRef archive);

// --- Inspection ---

/// Number of entries in the archive, or -1 on error.
int32_t sz_entry_count(SZArchiveRef archive);

/// Index of the entry an AppleDouble sidecar describes, or -1 when `index` is
/// not a sidecar for another entry of this archive. Sidecars carry a file's
/// extended attributes and resource fork, so they are that file's metadata: a
/// rewrite that drops the file has to drop them with it, or the archive keeps
/// metadata for something it no longer holds.
int32_t sz_sidecar_target(SZArchiveRef archive, uint32_t index);

typedef struct {
    uint32_t index;
    const char *path;        // UTF-8; pointer valid until sz_close()
    const char *name;        // UTF-8 filename only (no separators); valid until sz_close()
    int32_t parent_index;    // parent entry index, or -1 if root-level
    uint64_t size;           // uncompressed bytes
    uint64_t packed_size;    // compressed bytes
    uint32_t attributes;     // Windows file attributes
    uint32_t posix_permissions; // POSIX mode bits (lower 16 bits); 0 if unknown
    bool is_directory;
    bool is_encrypted;
    bool is_alt_stream;      // macOS extended attributes, NTFS alternate data streams
    int64_t mtime;           // Unix epoch seconds; -1 if unknown
} SZEntry;

/// Populate *entry_out for the entry at the given index.
/// Returns true on success.
bool sz_get_entry(SZArchiveRef archive, uint32_t index, SZEntry *entry_out);

// --- Password ---

/// Set the password used for extracting encrypted entries.
/// Pass NULL to clear a previously set password.
/// The string is copied internally -- caller retains ownership.
void sz_set_password(SZArchiveRef archive, const char *password);

// --- Extraction ---

/// Byte-level progress reported by 7-Zip during extraction.
/// `completed`/`total` are the handler's processed-bytes counters for the
/// whole operation (same unit for both). Return false to abort the
/// extraction — it stops at the next progress checkpoint and the extract
/// call returns SZ_EXTRACT_ABORTED.
/// Called on the extraction thread.
typedef bool (*sz_progress_callback)(uint64_t completed, uint64_t total,
                                     void *context);

/// Extract call result codes.
#define SZ_EXTRACT_OK 0
#define SZ_EXTRACT_FAILED (-1)
#define SZ_EXTRACT_ABORTED 2
/// At least one entry could not be decrypted with the password that was set
/// (or no password was set for an encrypted entry). Distinct from
/// SZ_EXTRACT_FAILED so callers can re-prompt instead of giving up.
#define SZ_EXTRACT_WRONG_PASSWORD 3

/// Extract a single entry by index into dest_dir (which must already exist).
/// Returns 0 on success. On failure, *error_out receives a malloc'd string.
int sz_extract_entry(SZArchiveRef archive, uint32_t index,
                     const char *dest_dir, char **error_out);

/// Extract multiple entries by index into dest_dir (which must already exist).
/// The indices array must be sorted in ascending order.
/// progress may be NULL. Returns SZ_EXTRACT_OK, SZ_EXTRACT_FAILED, or
/// SZ_EXTRACT_ABORTED (when the progress callback returned false).
int sz_extract_entries(SZArchiveRef archive, const uint32_t *indices,
                       uint32_t count, const char *dest_dir,
                       sz_progress_callback progress, void *progress_context,
                       char **error_out);

/// Extract all entries into dest_dir (which must already exist).
/// progress may be NULL. Returns SZ_EXTRACT_OK, SZ_EXTRACT_FAILED, or
/// SZ_EXTRACT_ABORTED (when the progress callback returned false).
int sz_extract_all(SZArchiveRef archive, const char *dest_dir,
                   sz_progress_callback progress, void *progress_context,
                   char **error_out);

// --- Tree support ---

/// Returns true if the archive natively provides parent-child relationships
/// (tree-based formats like NTFS, HFS+, Ext, APFS disk images).
/// When true, SZEntry::parent_index and SZEntry::name are populated from the
/// archive's native tree structure rather than derived from path strings.
bool sz_is_tree(SZArchiveRef archive);

// --- Utilities ---

/// Version of the vendored 7-Zip sources, e.g. "26.02".
/// Statically allocated -- do not free.
const char* sz_version(void);

// --- Archive Creation/Update ---

/// Operation type for each item in an update.
typedef enum {
    SZ_UPDATE_KEEP     = 0,  ///< Keep entry unchanged from source archive.
    SZ_UPDATE_MOVE     = 1,  ///< Keep data from source, change archive path.
    SZ_UPDATE_ADD_FILE = 2,  ///< Add new entry from a file on disk.
    SZ_UPDATE_ADD_DATA = 3,  ///< Add new entry from an in-memory buffer.
    SZ_UPDATE_ADD_DIR  = 4,  ///< Add an empty directory entry.
} SZUpdateOp;

/// Describes a single item in the output archive.
typedef struct {
    SZUpdateOp op;

    /// Index in the source archive (for KEEP, MOVE).
    uint32_t source_index;

    /// Path inside the output archive (for MOVE, ADD_FILE, ADD_DATA, ADD_DIR).
    /// UTF-8. Pointer must remain valid until sz_update_archive returns.
    const char *archive_path;

    /// Filesystem path to read data from (for ADD_FILE only). UTF-8.
    const char *disk_path;

    /// Pointer to in-memory data (for ADD_DATA only).
    const void *data;
    /// Size of in-memory data in bytes (for ADD_DATA only).
    uint64_t data_size;

    /// Whether the entry is a directory.
    bool is_directory;
    /// Modification time as Unix epoch seconds; -1 if unset.
    int64_t mtime;
    /// POSIX permission bits; 0 if unset.
    uint32_t posix_permissions;
} SZUpdateItem;

/// Compression options for archive creation/update.
typedef struct {
    /// Format name: "7z" or "zip". UTF-8.
    const char *format;
    /// Compression level 0 (store) through 9 (ultra).
    uint32_t level;
    /// Compression method name (e.g. "lzma2", "deflate"). NULL for format default.
    const char *method;
    /// Solid mode: 1=on, 0=off, -1=format default.
    int8_t solid_mode;
} SZCompressionOptions;

/// Create or update an archive from a list of update items.
///
/// @param source_path  Path to the source archive (NULL to create a new archive).
/// @param dest_path    Path for the output archive file.
/// @param items        Array of update item descriptors.
/// @param item_count   Number of items in the array.
/// @param options      Compression options.
/// @param progress     Optional byte-progress callback (NULL to skip). Return
///                     false to abort — the write stops and returns non-zero.
/// @param progress_context  Passed back to `progress`.
/// @param error_out    On failure, receives a malloc'd UTF-8 error string (caller must free).
/// @return 0 on success, non-zero on failure.
int sz_update_archive(
    const char *source_path,
    const char *dest_path,
    const SZUpdateItem *items,
    uint32_t item_count,
    const SZCompressionOptions *options,
    sz_progress_callback progress,
    void *progress_context,
    char **error_out
);

#ifdef __cplusplus
}
#endif
