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
/// Returns NULL on failure. On failure, *error_out (if non-NULL) is set to a
/// malloc'd UTF-8 error string -- caller must free() it.
SZArchiveRef sz_open(const char *path, char **error_out);

/// Release all resources. Must be called exactly once per successful sz_open().
void sz_close(SZArchiveRef archive);

// --- Inspection ---

/// Number of entries in the archive, or -1 on error.
int32_t sz_entry_count(SZArchiveRef archive);

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

/// Extract a single entry by index into dest_dir (which must already exist).
/// Returns 0 on success. On failure, *error_out receives a malloc'd string.
int sz_extract_entry(SZArchiveRef archive, uint32_t index,
                     const char *dest_dir, char **error_out);

/// Extract multiple entries by index into dest_dir (which must already exist).
/// The indices array must be sorted in ascending order.
/// Returns 0 on success. On failure, *error_out receives a malloc'd string.
int sz_extract_entries(SZArchiveRef archive, const uint32_t *indices,
                       uint32_t count, const char *dest_dir, char **error_out);

/// Extract all entries into dest_dir (which must already exist).
/// Returns 0 on success.
int sz_extract_all(SZArchiveRef archive, const char *dest_dir,
                   char **error_out);

// --- Tree support ---

/// Returns true if the archive natively provides parent-child relationships
/// (tree-based formats like NTFS, HFS+, Ext, APFS disk images).
/// When true, SZEntry::parent_index and SZEntry::name are populated from the
/// archive's native tree structure rather than derived from path strings.
bool sz_is_tree(SZArchiveRef archive);

// --- Utilities ---

/// Statically allocated version string -- do not free.
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
/// @param error_out    On failure, receives a malloc'd UTF-8 error string (caller must free).
/// @return 0 on success, non-zero on failure.
int sz_update_archive(
    const char *source_path,
    const char *dest_path,
    const SZUpdateItem *items,
    uint32_t item_count,
    const SZCompressionOptions *options,
    char **error_out
);

#ifdef __cplusplus
}
#endif
