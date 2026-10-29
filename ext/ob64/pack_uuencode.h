#ifndef PACK_UUENCODE_H
#define PACK_UUENCODE_H

#include <stddef.h>

size_t pack_uuencode_encode(const char *src, size_t srclen, char *out);
/* Encodes like native pack("u") with line_len (a multiple of 3, 3..63) bytes per line; returns the length */
size_t pack_uuencode_lines(const char *src, size_t srclen, char *out, size_t line_len);
size_t pack_uuencode_decode(const char *src, size_t srclen, char *out);
/* Upper bound of the decoded length of srclen chars: srclen * 3 / 4 without overflow */
size_t pack_uudecode_cap(size_t srclen);
/*
 * Decodes like native unpack("u") with the output capped at cap bytes (natively
 * pack_uudecode_cap(srclen)) and returns the decoded length. out needs cap + 3
 * bytes; NULL computes the length only. *stopped: 1 if decoding ended before
 * the end of src (a line not starting with a char in '!'..'`'), 0 otherwise.
 */
size_t pack_uudecode_lines_capped(const char *src, size_t srclen, char *out, size_t cap, int *stopped);
/* pack_uudecode_lines_capped with cap pack_uudecode_cap(srclen) */
size_t pack_uudecode_lines(const char *src, size_t srclen, char *out);

#endif /* PACK_UUENCODE_H */
