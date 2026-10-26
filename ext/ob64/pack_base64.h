#ifndef PACK_BASE64_H
#define PACK_BASE64_H

#include <stddef.h>

/* Flags for SIMD-accelerated codec */
#define PACK_BASE64_URL_SAFE  (1 << 0)  /* use URL-safe alphabet (RFC 4648 §5) */
#define PACK_BASE64_LOOSE     (1 << 1)  /* accept both padded and unpadded input */

/* Codecs, worst to best; scalar is plain C */
enum pack_codec {
	PACK_CODEC_SCALAR,
	PACK_CODEC_AVX2,
	PACK_CODEC_AVX512,
	PACK_CODEC_NEON64,
	PACK_CODECS
};

int pack_codec_runnable(enum pack_codec codec);
enum pack_codec pack_codec_current(void);
/* Caller ensures the codec is runnable */
void pack_codec_set(enum pack_codec codec);

/* SIMD-accelerated streaming codec (strict, unwrapped) */
void pack_base64_init(void);
size_t pack_base64_encode(const char *src, size_t srclen, char *out, int flags);
int pack_base64_decode(const char *src, size_t srclen, char *out, size_t *outlen, int flags);

/* RFC 2045 codec (m with line wrapping, lenient decode) */
/* Lines end in "\r\n" if crlf, "\n" otherwise */
size_t pack_base64_encode_rfc2045(const char *src, size_t srclen, char *out, int bytes_per_line, int crlf);
size_t pack_base64_decode_rfc2045(const char *src, size_t srclen, char *out);
/* Length pack_base64_decode_rfc2045 would return; reads all of src */
size_t pack_base64_decoded_length_rfc2045(const char *src, size_t srclen);

#endif /* PACK_BASE64_H */
