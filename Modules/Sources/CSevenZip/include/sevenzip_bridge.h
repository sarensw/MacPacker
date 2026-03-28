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
    uint64_t size;           // uncompressed bytes
    uint64_t packed_size;    // compressed bytes
    uint32_t attributes;     // Windows file attributes
    uint32_t posix_permissions; // POSIX mode bits (lower 16 bits); 0 if unknown
    bool is_directory;
    bool is_encrypted;
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

/// Extract all entries into dest_dir (which must already exist).
/// Returns 0 on success.
int sz_extract_all(SZArchiveRef archive, const char *dest_dir,
                   char **error_out);

// --- Utilities ---

/// Statically allocated version string -- do not free.
const char* sz_version(void);

#ifdef __cplusplus
}
#endif
