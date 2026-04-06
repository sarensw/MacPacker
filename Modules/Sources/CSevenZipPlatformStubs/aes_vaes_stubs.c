//
//  aes_vaes_stubs.c
//  Modules
//
//  Created by Stephan Arenswald on 06.04.26.
//

// aes_vaes_stubs.c -- Stubs for VAES/AVX2 AES functions referenced on x86_64.
//
// When compiling for x86_64 with Clang >= 8, 7-zip's Aes.c defines
// USE_HW_VAES and references AesCbc_Decode_HW_256 / AesCtr_Code_HW_256.
// These are normally provided by AesOpt.c (which is excluded from the
// SPM build because it uses architecture-specific intrinsics).
// The base AES implementation detects at runtime that these function
// pointers are NULL-equivalent and falls back to software.

#include <stdint.h>
#include <stddef.h>

typedef uint32_t UInt32;
typedef uint8_t  Byte;

void AesCbc_Decode_HW_256(UInt32 *p, Byte *data, size_t numBlocks)
{ (void)p; (void)data; (void)numBlocks; }

void AesCtr_Code_HW_256(UInt32 *p, Byte *data, size_t numBlocks)
{ (void)p; (void)data; (void)numBlocks; }
