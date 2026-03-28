// hw_stubs.c -- Stubs for hardware-accelerated functions.
// These are normally provided by the Opt files (AesOpt.c, Sha*Opt.c, SwapBytes.c)
// but those files use architecture-specific intrinsics that don't
// cross-compile cleanly between arm64 and x86_64 under SPM.
// The base C implementations in Aes.c, Sha1.c, etc. detect at runtime
// that HW functions are NULL/unavailable and use software fallbacks.

#include "Precomp.h"
#include "CpuArch.h"

#include <stdint.h>
#include <stddef.h>

typedef uint32_t UInt32;
typedef uint8_t Byte;

// AES hardware stubs
void Z7_FASTCALL AesCbc_Encode_HW(UInt32 *p, Byte *data, size_t numBlocks)
{ (void)p; (void)data; (void)numBlocks; }
void Z7_FASTCALL AesCbc_Decode_HW(UInt32 *p, Byte *data, size_t numBlocks)
{ (void)p; (void)data; (void)numBlocks; }
void Z7_FASTCALL AesCtr_Code_HW(UInt32 *p, Byte *data, size_t numBlocks)
{ (void)p; (void)data; (void)numBlocks; }

// SHA hardware stubs
void Z7_FASTCALL Sha1_UpdateBlocks_HW(UInt32 *state, const Byte *data, size_t numBlocks)
{ (void)state; (void)data; (void)numBlocks; }
void Z7_FASTCALL Sha256_UpdateBlocks_HW(UInt32 *state, const Byte *data, size_t numBlocks)
{ (void)state; (void)data; (void)numBlocks; }
void Z7_FASTCALL Sha512_UpdateBlocks_HW(UInt32 *state, const Byte *data, size_t numBlocks)
{ (void)state; (void)data; (void)numBlocks; }

// SwapBytes stubs
void z7_SwapBytesPrepare(void) {}
void z7_SwapBytes2(Byte *data, size_t numItems) { (void)data; (void)numItems; }
void z7_SwapBytes4(Byte *data, size_t numItems) { (void)data; (void)numItems; }
