#ifndef MACPACKER_DAR_BRIDGE_H
#define MACPACKER_DAR_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// One operation owns its results. Only cancel may run concurrently with read/extract.
typedef struct mp_dar_operation mp_dar_operation;
mp_dar_operation *mp_dar_create(void);
void mp_dar_free(mp_dar_operation *operation);
void mp_dar_cancel(mp_dar_operation *operation);
const char *mp_dar_version(void);
// 0: success, 1: error, 2: password needed/wrong, 3: cancelled.
int mp_dar_read(mp_dar_operation *, const char *folder, const char *base, const char *extension, unsigned digits, const char *password);
int mp_dar_extract(mp_dar_operation *, const char *folder, const char *base, const char *extension, unsigned digits, const char *password, const char *destination, const char *const *selection, size_t count);
const char *mp_dar_error(const mp_dar_operation *);
size_t mp_dar_count(const mp_dar_operation *);
const char *mp_dar_path(const mp_dar_operation *, size_t index);
const char *mp_dar_link(const mp_dar_operation *, size_t index);
uint64_t mp_dar_size(const mp_dar_operation *, size_t index);
uint64_t mp_dar_packed_size(const mp_dar_operation *, size_t index);
int64_t mp_dar_mtime(const mp_dar_operation *, size_t index);
int mp_dar_kind(const mp_dar_operation *, size_t index);
int mp_dar_available(const mp_dar_operation *, size_t index);
int mp_dar_encrypted(const mp_dar_operation *);
#ifdef __cplusplus
}
#endif
#endif
