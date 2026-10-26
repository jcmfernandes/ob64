/**********************************************************************

  Derived from aklomp/base64; license: see pack_base64.c.

  pack_generic.h - Shared portability macros and generic inner loops
                   for pack_base64.c and pack_uuencode.c

  Extracted from the duplicated code in both codecs.  Everything here
  is either a macro or a static-inline function so that the compiler
  can inline the hot inner loops into each codec's outer loop.

**********************************************************************/

#ifndef RUBY_PACK_GENERIC_H
#define RUBY_PACK_GENERIC_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>

/* ======================================================================
 * Portability macros
 * ====================================================================== */

/* Endian detection */
#if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__)
#  if (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#    define PACK_LITTLE_ENDIAN 1
#  else
#    define PACK_LITTLE_ENDIAN 0
#  endif
#else
#  define PACK_LITTLE_ENDIAN 0
#endif

#ifdef __LITTLE_ENDIAN__
#  undef  PACK_LITTLE_ENDIAN
#  define PACK_LITTLE_ENDIAN 1
#endif

#ifdef __BIG_ENDIAN__
#  undef  PACK_LITTLE_ENDIAN
#  define PACK_LITTLE_ENDIAN 0
#endif

/* Endian conversion */
#if PACK_LITTLE_ENDIAN
#  define PACK_HTOBE32(x)  __builtin_bswap32(x)
#  define PACK_HTOBE64(x)  __builtin_bswap64(x)
#else
#  define PACK_HTOBE32(x)  (x)
#  define PACK_HTOBE64(x)  (x)
#endif

/* Word size detection */
#if defined(__x86_64__) || defined(__aarch64__) || defined(_M_X64) || defined(_M_ARM64)
#  define PACK_WORDSIZE 64
#elif SIZE_MAX == UINT64_MAX
#  define PACK_WORDSIZE 64
#elif SIZE_MAX == UINT32_MAX
#  define PACK_WORDSIZE 32
#else
#  define PACK_WORDSIZE 32
#endif

/* Force inline */
#ifdef _MSC_VER
#  define PACK_FORCE_INLINE  __forceinline
#else
#  define PACK_FORCE_INLINE  inline __attribute__((always_inline))
#endif

/* ======================================================================
 * Generic inner loop functions (table-parameterized)
 * ====================================================================== */

/* 64-bit encode inner: reads 8 bytes, consumes 6, produces 8 */
#if PACK_WORDSIZE == 64
static PACK_FORCE_INLINE void
pack_enc_loop_64_inner(const uint8_t **s, uint8_t **o, const uint16_t *enc_12bit)
{
	uint64_t src;

	memcpy(&src, *s, sizeof(src));
	src = PACK_HTOBE64(src);

	const size_t index0 = (src >> 52) & 0xFFFU;
	const size_t index1 = (src >> 40) & 0xFFFU;
	const size_t index2 = (src >> 28) & 0xFFFU;
	const size_t index3 = (src >> 16) & 0xFFFU;

	memcpy(*o + 0, enc_12bit + index0, 2);
	memcpy(*o + 2, enc_12bit + index1, 2);
	memcpy(*o + 4, enc_12bit + index2, 2);
	memcpy(*o + 6, enc_12bit + index3, 2);

	*s += 6;
	*o += 8;
}
#endif

/* 32-bit encode inner: reads 4 bytes, consumes 3, produces 4 */
static PACK_FORCE_INLINE void
pack_enc_loop_32_inner(const uint8_t **s, uint8_t **o, const uint16_t *enc_12bit)
{
	uint32_t src;

	memcpy(&src, *s, sizeof(src));
	src = PACK_HTOBE32(src);

	const size_t index0 = (src >> 20) & 0xFFFU;
	const size_t index1 = (src >>  8) & 0xFFFU;

	memcpy(*o + 0, enc_12bit + index0, 2);
	memcpy(*o + 2, enc_12bit + index1, 2);

	*s += 3;
	*o += 4;
}

/* 32-bit decode inner: reads 4 encoded bytes, writes 3 decoded bytes.
 * Returns 1 on success, 0 on invalid input. */
static PACK_FORCE_INLINE int
pack_dec_loop_32_inner(const uint8_t **s, uint8_t **o,
	const uint32_t *d0, const uint32_t *d1,
	const uint32_t *d2, const uint32_t *d3)
{
	const uint32_t str
		= d0[(*s)[0]]
		| d1[(*s)[1]]
		| d2[(*s)[2]]
		| d3[(*s)[3]];

#if PACK_LITTLE_ENDIAN
	if (str & UINT32_C(0x80000000)) {
		return 0;
	}
#else
	if (str & UINT32_C(1)) {
		return 0;
	}
#endif
	memcpy(*o, &str, sizeof(str));

	*s += 4;
	*o += 3;

	return 1;
}

#endif /* RUBY_PACK_GENERIC_H */
