/*
 * Checks every SIMD codec against scalar, the codec the Ruby specs check
 * against Ruby. Run under AddressSanitizer: each input and output gets a
 * buffer of exactly the size the Ruby glue allocates, so any read or write
 * past one fails. The Ruby specs can't show this for small strings: Ruby
 * keeps them inside larger blocks.
 *
 *   codecs_test [seed [rounds]]
 *
 * OB64_CODECS (e.g. "scalar,avx2,avx512") fails the run unless exactly
 * these codecs are runnable.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "pack_base64.h"
#include "pack_uuencode.h"

static const char *codec_names[PACK_CODECS] = { "scalar", "avx2", "avx512", "neon64" };

static unsigned long long rng_state;

static unsigned long long
rnd(void)
{
	/* xorshift64* */
	rng_state ^= rng_state >> 12;
	rng_state ^= rng_state << 25;
	rng_state ^= rng_state >> 27;
	return rng_state * 2685821657736338717ULL;
}

/* 0..n-1 */
static size_t
below(size_t n)
{
	return (size_t)(rnd() % n);
}

/* An exact-size copy, so ASan catches reads past it */
static char *
exact(const char *s, size_t n)
{
	char *p = malloc(n);

	if (!p && n) abort();
	if (n) memcpy(p, s, n);
	return p;
}

struct result {
	int ok;
	size_t len;
	char *buf;
	int stopped;
};

static unsigned long long seed;
static size_t failures;

static void
check(const char *op, int codec, const char *in, size_t inlen, struct result want, struct result got)
{
	if (want.ok == got.ok && want.stopped == got.stopped &&
	    (!want.ok || (want.len == got.len && !memcmp(want.buf, got.buf, want.len)))) {
		return;
	}

	fprintf(stderr, "FAIL %s, %s, input length %zu, seed %llu: scalar ok=%d len=%zu stopped=%d, %s ok=%d len=%zu stopped=%d\n",
		op, codec_names[codec], inlen, seed, want.ok, want.len, want.stopped, codec_names[codec], got.ok, got.len,
		got.stopped);
	fprintf(stderr, "  input:");
	for (size_t i = 0; i < inlen && i < 64; i++) fprintf(stderr, " %02x", (unsigned char)in[i]);
	fprintf(stderr, "%s\n", inlen > 64 ? " ..." : "");
	if (++failures >= 10) exit(1);
}

/* Output buffers: what the Ruby glue allocates, plus Ruby's terminator byte */

static struct result
encode(const char *in, size_t n, int flags)
{
	struct result r = { 1, 0, malloc((n + 2) / 3 * 4 + 1), 0 };

	r.len = pack_base64_encode(in, n, r.buf, flags);
	return r;
}

static struct result
decode(const char *in, size_t n, int flags)
{
	/* The smaller of ob64_ext.c's and ob64_pack.c's */
	struct result r = { 0, 0, malloc((n + 3) / 4 * 3 + 1), 0 };

	r.ok = pack_base64_decode(in, n, r.buf, &r.len, flags);
	return r;
}

static struct result
encode_rfc2045(const char *in, size_t n, int bytes_per_line, int crlf)
{
	size_t lines = (n + bytes_per_line - 1) / bytes_per_line;
	struct result r = { 1, 0, malloc((n + 2) / 3 * 4 + lines * (crlf ? 2 : 1) + 1), 0 };

	r.len = pack_base64_encode_rfc2045(in, n, r.buf, bytes_per_line, crlf);
	return r;
}

static struct result
decode_rfc2045(const char *in, size_t n)
{
	struct result r = { 1, 0, malloc(n / 4 * 3 + 3 + 1), 0 };

	r.len = pack_base64_decode_rfc2045(in, n, r.buf);
	if (pack_base64_decoded_length_rfc2045(in, n) != r.len) {
		fprintf(stderr, "FAIL decoded_length_rfc2045 != decode_rfc2045, input length %zu, seed %llu\n", n, seed);
		exit(1);
	}
	return r;
}

static struct result
uuencode(const char *in, size_t n, size_t line_len)
{
	size_t lines = (n + line_len - 1) / line_len;
	struct result r = { 1, 0, malloc((n + 2) / 3 * 4 + lines * 2 + 1), 0 };

	r.len = pack_uuencode_lines(in, n, r.buf, line_len);
	return r;
}

static struct result
uudecode(const char *in, size_t n)
{
	struct result r = { 1, 0, malloc(pack_uudecode_cap(n) + 3 + 1), 0 };

	r.len = pack_uudecode_lines(in, n, r.buf);
	if (pack_uudecode_lines(in, n, NULL) != r.len) {
		fprintf(stderr, "FAIL uudecode length != uudecode, input length %zu, seed %llu\n", n, seed);
		exit(1);
	}
	return r;
}

static struct result
uudecode_capped(const char *in, size_t n, size_t cap)
{
	struct result r = { 1, 0, malloc(cap + 3 + 1), 0 };
	int stopped;

	r.len = pack_uudecode_lines_capped(in, n, r.buf, cap, &r.stopped);
	if (pack_uudecode_lines_capped(in, n, NULL, cap, &stopped) != r.len || stopped != r.stopped) {
		fprintf(stderr, "FAIL uudecode_capped length != uudecode_capped, input length %zu, seed %llu\n", n, seed);
		exit(1);
	}
	return r;
}

static int codecs[PACK_CODECS];
static int ncodecs;

enum op { ENCODE, ENCODE_URL, DECODE, DECODE_URL, DECODE_LOOSE, DECODE_URL_LOOSE, ENCODE_RFC2045, DECODE_RFC2045, UUENCODE, UUDECODE, UUDECODE_CAPPED };

static const char *op_names[] = {
	"encode", "encode url", "decode", "decode url", "decode loose", "decode url loose",
	"encode_rfc2045", "decode_rfc2045", "uuencode", "uudecode", "uudecode_capped"
};

static struct result
run(enum op op, const char *in, size_t n, int arg, int crlf)
{
	switch (op) {
	case ENCODE: return encode(in, n, 0);
	case ENCODE_URL: return encode(in, n, PACK_BASE64_URL_SAFE);
	case DECODE: return decode(in, n, 0);
	case DECODE_URL: return decode(in, n, PACK_BASE64_URL_SAFE);
	case DECODE_LOOSE: return decode(in, n, PACK_BASE64_LOOSE);
	case DECODE_URL_LOOSE: return decode(in, n, PACK_BASE64_URL_SAFE | PACK_BASE64_LOOSE);
	case ENCODE_RFC2045: return encode_rfc2045(in, n, arg, crlf);
	case DECODE_RFC2045: return decode_rfc2045(in, n);
	case UUENCODE: return uuencode(in, n, (size_t)arg);
	case UUDECODE: return uudecode(in, n);
	case UUDECODE_CAPPED: return uudecode_capped(in, n, (size_t)arg);
	}
	abort();
}

/* Runs op on every codec and compares each with scalar */
static void
compare(enum op op, const char *src, size_t n, int arg, int crlf)
{
	char *in = exact(src, n);
	struct result want;

	pack_codec_set(PACK_CODEC_SCALAR);
	want = run(op, in, n, arg, crlf);
	for (int i = 1; i < ncodecs; i++) {
		pack_codec_set(codecs[i]);
		struct result got = run(op, in, n, arg, crlf);
		check(op_names[op], codecs[i], in, n, want, got);
		free(got.buf);
	}
	free(want.buf);
	free(in);
}

static const char junk[] = "=\n\r \t\0\x80\xff-_+/!~aA";

/* Up to 3 random edits: insert, replace or delete, often with junk */
static size_t
mutate(char *s, size_t n, size_t cap)
{
	size_t edits = below(4);

	for (size_t e = 0; e < edits; e++) {
		size_t pos = below(n + 1);
		char c = below(2) ? junk[below(sizeof(junk) - 1)] : (char)rnd();

		switch (below(3)) {
		case 0:
			if (n == cap) break;
			memmove(s + pos + 1, s + pos, n - pos);
			s[pos] = c;
			n++;
			break;
		case 1:
			if (pos < n) s[pos] = c;
			break;
		default:
			if (pos < n) {
				memmove(s + pos, s + pos + 1, n - pos - 1);
				n--;
			}
		}
	}
	if (!below(8)) n = below(n + 1);
	return n;
}

/* Decoder input: an encoding of n random bytes, sometimes broken */
static size_t
encoded(enum op op, char *bin, size_t n, char *out, size_t cap)
{
	size_t len;

	pack_codec_set(PACK_CODEC_SCALAR);
	switch (op) {
	case DECODE_URL:
	case DECODE_URL_LOOSE:
		len = pack_base64_encode(bin, n, out, PACK_BASE64_URL_SAFE);
		break;
	case DECODE_RFC2045:
		len = pack_base64_encode_rfc2045(bin, n, out, below(2) ? 45 : 3 * (1 + (int)below(100)), (int)below(2));
		break;
	case UUDECODE:
	case UUDECODE_CAPPED:
		len = pack_uuencode_lines(bin, n, out, below(2) ? 45 : 3 * (1 + below(21)));
		break;
	default:
		len = pack_base64_encode(bin, n, out, 0);
	}
	if (op == DECODE_LOOSE || op == DECODE_URL_LOOSE) {
		while (len && out[len - 1] == '=' && below(2)) len--;
	}
	return below(2) ? len : mutate(out, len, cap);
}

/* A cap for uudecode_capped: 0, small, up to the native one, the native one or larger */
static int
uu_cap(size_t n)
{
	size_t native = pack_uudecode_cap(n);

	switch (below(5)) {
	case 0: return 0;
	case 1: return (int)below(100);
	case 2: return (int)below(native + 1);
	case 3: return (int)native;
	default: return (int)(native + 1 + below(300));
	}
}

static void
round_of(size_t n, char *bin, char *enc, size_t cap)
{
	static const int rfc2045_lines[] = { 3, 45, 57, 300, 4998, 5001 };
	static const int uu_lines[] = { 3, 45, 63 };

	for (size_t i = 0; i < n; i++) bin[i] = (char)rnd();

	compare(ENCODE, bin, n, 0, 0);
	compare(ENCODE_URL, bin, n, 0, 0);
	compare(ENCODE_RFC2045, bin, n, rfc2045_lines[below(6)], (int)below(2));
	compare(UUENCODE, bin, n, uu_lines[below(3)], 0);

	for (enum op op = DECODE; op <= UUDECODE_CAPPED; op++) {
		if (op == ENCODE_RFC2045 || op == UUENCODE) continue;
		size_t len = encoded(op, bin, n, enc, cap);
		compare(op, enc, len, op == UUDECODE_CAPPED ? uu_cap(len) : 0, 0);
	}
	/* Random bytes */
	size_t len = below(n + 1);
	for (size_t i = 0; i < len; i++) enc[i] = (char)rnd();
	compare(DECODE, enc, len, 0, 0);
	compare(DECODE_RFC2045, enc, len, 0, 0);
	compare(UUDECODE, enc, len, 0, 0);
	compare(UUDECODE_CAPPED, enc, len, uu_cap(len), 0);
}

static void
check_codecs(void)
{
	const char *want = getenv("OB64_CODECS");
	char got[64] = "";

	for (int i = 0; i < ncodecs; i++) {
		if (i) strcat(got, ",");
		strcat(got, codec_names[codecs[i]]);
	}
	printf("codecs: %s\n", got);
	if (want && strcmp(want, got)) {
		fprintf(stderr, "FAIL codecs: expected %s\n", want);
		exit(1);
	}
}

int
main(int argc, char **argv)
{
	seed = argc > 1 ? strtoull(argv[1], NULL, 10) : (unsigned long long)time(NULL);
	long rounds = argc > 2 ? strtol(argv[2], NULL, 10) : 20000;
	enum { MAX = 70000 };
	/* Room for the longest encoding (uu, 3-byte lines) and inserts */
	size_t cap = MAX / 3 * 6 + 64;
	char *bin = malloc(MAX), *enc = malloc(cap);

	rng_state = seed | 1;
	pack_base64_init();
	for (int i = 0; i < PACK_CODECS; i++) {
		if (pack_codec_runnable(i)) codecs[ncodecs++] = i;
	}
	check_codecs();
	printf("seed: %llu\n", seed);

	/* Every small size, then random ones, mostly small */
	for (size_t n = 0; n <= 1100; n++) {
		for (int k = 0; k < 4; k++) round_of(n, bin, enc, cap);
	}
	for (long r = 0; r < rounds; r++) {
		size_t n = below(10) < 7 ? below(301) : below(10) < 8 ? below(10001) : below(MAX + 1);
		round_of(n, bin, enc, cap);
	}

	free(bin);
	free(enc);
	if (failures) return 1;
	printf("OK\n");
	return 0;
}
