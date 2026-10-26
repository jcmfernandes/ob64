#ifndef PACK_SIMD_H
#define PACK_SIMD_H

#include <stddef.h>
#include <stdint.h>

/* Selects the uuencode alphabet in bulk loops; base64 otherwise */
#define PACK_ALPHABET_UU (1 << 8)

/*
 * A SIMD codec's bulk loop. Consumes whole blocks only, advancing *s and *o
 * and adjusting *slen and *olen; the caller handles what is left. Decode
 * loops stop before a block holding an invalid char.
 */
typedef void (*pack_bulk_loop)(const uint8_t **s, size_t *slen, uint8_t **o, size_t *olen, int flags);

/* Bulk encode loop of the codec routing picks for size; NULL for plain C */
pack_bulk_loop pack_simd_enc_loop(size_t size);
/* Bulk decode loop of the codec routing picks for size; NULL for plain C */
pack_bulk_loop pack_simd_dec_loop(size_t size);

#endif /* PACK_SIMD_H */
