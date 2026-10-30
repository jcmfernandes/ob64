#include <limits.h>
#include "ob64.h"
#include "pack_uuencode.h"
#include "ruby/encoding.h"

#define COUNT_STAR (-1)

/*
 * Returns 'm' or 'u' if fmt is a String matching \A[mu](\d{1,9}|\*)?\z in an
 * ASCII-compatible encoding, 0 otherwise. *count: 1 if absent, COUNT_STAR for '*'.
 */
static int
parse_format(VALUE fmt, long *count)
{
  if (!RB_TYPE_P(fmt, T_STRING) || !rb_enc_str_asciicompat_p(fmt)) return 0;

  const char *p = RSTRING_PTR(fmt);
  long len = RSTRING_LEN(fmt);

  if (len < 1 || len > 10 || (p[0] != 'm' && p[0] != 'u')) return 0;
  if (len == 1) {
    *count = 1;
  }
  else if (len == 2 && p[1] == '*') {
    *count = COUNT_STAR;
  }
  else {
    *count = 0;
    for (long i = 1; i < len; i++) {
      if (p[i] < '0' || p[i] > '9') return 0;
      *count = *count * 10 + (p[i] - '0');
    }
  }

  return p[0];
}

/* Makes res a US-ASCII String, as native pack does */
static VALUE
ascii_result(VALUE res)
{
  ENCODING_CODERANGE_SET(res, rb_usascii_encindex(), ENC_CODERANGE_7BIT);

  return res;
}

/* Per line of line_len bytes (a multiple of 3): a length byte, 4 chars per 3 bytes and a newline */
static long
uuencoded_length(long len, long line_len)
{
  ob64_check_encode_len((size_t)len);
  long full = len / line_len, rest = len % line_len;

  return full * (line_len / 3 * 4 + 2) + (rest ? (rest + 2) / 3 * 4 + 2 : 0);
}

/* Appends the uuencode of src[off, len], line_len bytes per line, to dst */
static void
uuencode_append(VALUE dst, VALUE src, long off, long len, long line_len)
{
  long dst_len = RSTRING_LEN(dst);
  char *out = ob64_reserve(dst, uuencoded_length(len, line_len));
  size_t n = pack_uuencode_lines(RSTRING_PTR(src) + off, (size_t)len, out, (size_t)line_len);
  RB_GC_GUARD(src);

  rb_str_set_len(dst, dst_len + (long)n);
}

static VALUE
uuencode(VALUE from, long line_len)
{
  VALUE res = rb_str_buf_new(0);

  uuencode_append(res, from, 0, RSTRING_LEN(from), line_len);

  return ascii_result(res);
}

/* line_bytes: bytes per line, a multiple of 3; 4 chars per 3 bytes, a line break per line */
static long
encoded_length_rfc2045(long len, long line_bytes, int crlf)
{
  ob64_check_encode_len((size_t)len);

  return (len + 2) / 3 * 4 + (len + line_bytes - 1) / line_bytes * (crlf ? 2 : 1);
}

/* Appends the encode of src[off, len] to dst; line_bytes as above, crlf: lines end in "\r\n" */
static void
encode_rfc2045_append(VALUE dst, VALUE src, long off, long len, long line_bytes, int crlf)
{
  long dst_len = RSTRING_LEN(dst);
  char *out = ob64_reserve(dst, encoded_length_rfc2045(len, line_bytes, crlf));
  size_t n = pack_base64_encode_rfc2045(RSTRING_PTR(src) + off, (size_t)len, out, (int)line_bytes, crlf);
  RB_GC_GUARD(src);

  rb_str_set_len(dst, dst_len + (long)n);
}

static VALUE
base64_encode_rfc2045(VALUE from, long line_bytes, int crlf)
{
  VALUE res = rb_str_buf_new(0);

  encode_rfc2045_append(res, from, 0, RSTRING_LEN(from), line_bytes, crlf);

  return ascii_result(res);
}

static VALUE
Ob64_pack(int argc, VALUE *argv, VALUE ary)
{
  long count, plen;
  int type;
  VALUE from;

  if (argc != 1 || rb_keyword_given_p() || rb_block_given_p() ||
      !(type = parse_format(argv[0], &count)) ||
      RARRAY_LEN(ary) < 1 || !RB_TYPE_P(from = RARRAY_AREF(ary, 0), T_STRING) ||
      /* Bound plen so the output size below cannot overflow */
      (plen = RSTRING_LEN(from)) > LONG_MAX / 4) {
    return rb_call_super_kw(argc, argv, RB_PASS_CALLED_KEYWORDS);
  }

  if (type == 'm' && count == 0) {
    VALUE res = rb_str_buf_new(0);

    ob64_encode_append(res, from, 0, plen, Qfalse, Qtrue);

    return ascii_result(res);
  }

  long len = count;

  /* '*' gets 45, as natively */
  if (len <= 2) len = 45;
  else if (len > 63 && type == 'u') len = 63;
  else len = len / 3 * 3;

  return type == 'u' ? uuencode(from, len) : base64_encode_rfc2045(from, len, 0);
}

static VALUE
uudecode(VALUE str)
{
  long len = RSTRING_LEN(str);
  /* +3: the decoder stores up to 3 bytes past a line's decoded length */
  VALUE buf = rb_str_buf_new((long)pack_uudecode_cap((size_t)len) + 3);
  size_t total = pack_uudecode_lines(RSTRING_PTR(str), (size_t)len, RSTRING_PTR(buf));
  RB_GC_GUARD(str);

  rb_str_set_len(buf, (long)total);

  return buf;
}

static VALUE
base64_decode(VALUE str, long count)
{
  long len = RSTRING_LEN(str);
  /* Room for unpadded input and decoder overruns */
  VALUE buf = rb_str_buf_new(len / 4 * 3 + 3);
  size_t n;

  if (count == 0) {
    if (!pack_base64_decode(RSTRING_PTR(str), (size_t)len, RSTRING_PTR(buf), &n, 0)) {
      rb_raise(rb_eArgError, "invalid base64");
    }
  }
  else {
    n = pack_base64_decode_rfc2045(RSTRING_PTR(str), (size_t)len, RSTRING_PTR(buf));
  }
  RB_GC_GUARD(str);

  rb_str_set_len(buf, (long)n);

  return buf;
}

/* Returns the decoded String, or Qundef when native Ruby must handle the call */
static VALUE
unpack_fast(int argc, VALUE *argv, VALUE str)
{
  long count;
  int type;

  if (argc != 1 || rb_keyword_given_p() || rb_block_given_p() ||
      !(type = parse_format(argv[0], &count))) {
    return Qundef;
  }

  return type == 'm' ? base64_decode(str, count) : uudecode(str);
}

static VALUE
Ob64_unpack(int argc, VALUE *argv, VALUE str)
{
  VALUE res = unpack_fast(argc, argv, str);

  if (RB_UNDEF_P(res)) return rb_call_super_kw(argc, argv, RB_PASS_CALLED_KEYWORDS);

  return rb_ary_new_from_values(1, &res);
}

static VALUE
Ob64_unpack1(int argc, VALUE *argv, VALUE str)
{
  VALUE res = unpack_fast(argc, argv, str);

  if (RB_UNDEF_P(res)) return rb_call_super_kw(argc, argv, RB_PASS_CALLED_KEYWORDS);

  return res;
}

/* Bytes per line for a line_length in chars; validates it */
static long
rfc2045_line_bytes(VALUE line_length)
{
  long chars = NUM2LONG(line_length);

  if (chars < 4 || chars % 4 || chars / 4 * 3 > INT_MAX) {
    rb_raise(rb_eArgError, "line length must be a positive multiple of 4: %ld", chars);
  }

  return chars / 4 * 3;
}

static VALUE
Ob64_encode_rfc_2045(VALUE self, VALUE bin, VALUE line_length, VALUE crlf)
{
  long line_bytes = rfc2045_line_bytes(line_length);

  StringValue(bin);

  return base64_encode_rfc2045(bin, line_bytes, RTEST(crlf));
}

static VALUE
Ob64_encode_rfc_2045_into(VALUE self, VALUE dst, VALUE src, VALUE off, VALUE len, VALUE line_length, VALUE crlf)
{
  StringValue(dst);
  StringValue(src);
  long o = NUM2LONG(off);
  long n = ob64_src_range(dst, src, o, len);

  encode_rfc2045_append(dst, src, o, n, rfc2045_line_bytes(line_length), RTEST(crlf));
  RB_GC_GUARD(dst);

  return dst;
}

/* Appends the decode of src[0, len] to dst; returns the bytes appended */
static size_t
decode_rfc2045_append(VALUE dst, VALUE src, long len)
{
  long dst_len = RSTRING_LEN(dst);
  /* Room for unpadded input and decoder overruns */
  char *out = ob64_reserve(dst, len / 4 * 3 + 3);
  size_t n = pack_base64_decode_rfc2045(RSTRING_PTR(src), (size_t)len, out);
  RB_GC_GUARD(src);

  rb_str_set_len(dst, dst_len + (long)n);

  return n;
}

static VALUE
Ob64_decode_rfc_2045(VALUE self, VALUE string)
{
  StringValue(string);
  VALUE res = rb_str_buf_new(0);

  decode_rfc2045_append(res, string, RSTRING_LEN(string));

  return res;
}

static VALUE
Ob64_decode_rfc_2045_into(VALUE self, VALUE dst, VALUE src, VALUE len)
{
  StringValue(dst);
  StringValue(src);
  size_t n = decode_rfc2045_append(dst, src, ob64_src_range(dst, src, 0, len));
  RB_GC_GUARD(dst);

  return SIZET2NUM(n);
}

static VALUE
Ob64_encoded_length_of_rfc_2045(VALUE self, VALUE bin, VALUE line_length, VALUE crlf)
{
  long line_bytes = rfc2045_line_bytes(line_length);

  StringValue(bin);

  return LONG2NUM(encoded_length_rfc2045(RSTRING_LEN(bin), line_bytes, RTEST(crlf)));
}

static VALUE
Ob64_decoded_length_of_rfc_2045(VALUE self, VALUE string)
{
  StringValue(string);
  size_t n = pack_base64_decoded_length_rfc2045(RSTRING_PTR(string), (size_t)RSTRING_LEN(string));
  RB_GC_GUARD(string);

  return SIZET2NUM(n);
}

static VALUE
Ob64_uuencode(VALUE self, VALUE bin)
{
  StringValue(bin);

  return uuencode(bin, 45);
}

static VALUE
Ob64_uuencode_into(VALUE self, VALUE dst, VALUE src, VALUE off, VALUE len)
{
  StringValue(dst);
  StringValue(src);
  long o = NUM2LONG(off);

  uuencode_append(dst, src, o, ob64_src_range(dst, src, o, len), 45);
  RB_GC_GUARD(dst);

  return dst;
}

static VALUE
Ob64_uudecode(VALUE self, VALUE string)
{
  StringValue(string);

  return uudecode(string);
}

/*
 * Appends the uudecode of src[0, len], capped at cap bytes, to dst; returns
 * whether decoding ended before the end
 */
static VALUE
uudecode_capped_append(VALUE dst, VALUE src, long len, long c)
{
  if (c < 0) rb_raise(rb_eArgError, "negative cap: %ld", c);

  /* Lines take 2+ chars (the last one 1+) and decode to 63 bytes at most: a larger cap is the same */
  long lines = (len + 1) / 2;
  if (c / 63 > lines) c = lines * 63;

  long dst_len = RSTRING_LEN(dst);
  int stopped;
  /* +3: the decoder stores up to 3 bytes past a line's decoded length */
  char *out = ob64_reserve(dst, c + 3);
  size_t total = pack_uudecode_lines_capped(RSTRING_PTR(src), (size_t)len, out, (size_t)c, &stopped);
  RB_GC_GUARD(src);

  rb_str_set_len(dst, dst_len + (long)total);

  return stopped ? Qtrue : Qfalse;
}

/* Returns [decoded, stopped]: uudecode with the output capped at cap bytes; stopped: decoding ended before the end */
static VALUE
Ob64_uudecode_capped(VALUE self, VALUE string, VALUE cap)
{
  long c = NUM2LONG(cap);

  StringValue(string);
  VALUE buf = rb_str_buf_new(0);
  VALUE stopped = uudecode_capped_append(buf, string, RSTRING_LEN(string), c);

  return rb_assoc_new(buf, stopped);
}

static VALUE
Ob64_uudecode_capped_into(VALUE self, VALUE dst, VALUE src, VALUE len, VALUE cap)
{
  long c = NUM2LONG(cap);

  StringValue(dst);
  StringValue(src);
  long n = ob64_src_range(dst, src, 0, len);
  VALUE stopped = uudecode_capped_append(dst, src, n, c);
  RB_GC_GUARD(dst);

  return stopped;
}

static VALUE
Ob64_uuencoded_length_of(VALUE self, VALUE bin)
{
  StringValue(bin);

  return LONG2NUM(uuencoded_length(RSTRING_LEN(bin), 45));
}

static VALUE
Ob64_uudecoded_length_of(VALUE self, VALUE string)
{
  StringValue(string);
  size_t total = pack_uudecode_lines(RSTRING_PTR(string), (size_t)RSTRING_LEN(string), NULL);
  RB_GC_GUARD(string);

  return LONG2NUM((long)total);
}

void
Init_ob64_pack(VALUE mExt)
{
  VALUE mPack = rb_define_module_under(mExt, "Pack");
  VALUE mUnpack = rb_define_module_under(mExt, "Unpack");

  rb_define_method(mPack, "pack", Ob64_pack, -1);
  rb_define_method(mUnpack, "unpack", Ob64_unpack, -1);
  rb_define_method(mUnpack, "unpack1", Ob64_unpack1, -1);

  rb_define_private_method(mExt, "__encode_rfc_2045", Ob64_encode_rfc_2045, 3);
  rb_define_private_method(mExt, "__encode_rfc_2045_into", Ob64_encode_rfc_2045_into, 6);
  rb_define_private_method(mExt, "__decode_rfc_2045", Ob64_decode_rfc_2045, 1);
  rb_define_private_method(mExt, "__decode_rfc_2045_into", Ob64_decode_rfc_2045_into, 3);
  rb_define_private_method(mExt, "__encoded_length_of_rfc_2045", Ob64_encoded_length_of_rfc_2045, 3);
  rb_define_private_method(mExt, "__decoded_length_of_rfc_2045", Ob64_decoded_length_of_rfc_2045, 1);
  rb_define_private_method(mExt, "__uuencode", Ob64_uuencode, 1);
  rb_define_private_method(mExt, "__uuencode_into", Ob64_uuencode_into, 4);
  rb_define_private_method(mExt, "__uudecode", Ob64_uudecode, 1);
  rb_define_private_method(mExt, "__uudecode_capped", Ob64_uudecode_capped, 2);
  rb_define_private_method(mExt, "__uudecode_capped_into", Ob64_uudecode_capped_into, 4);
  rb_define_private_method(mExt, "__uuencoded_length_of", Ob64_uuencoded_length_of, 1);
  rb_define_private_method(mExt, "__uudecoded_length_of", Ob64_uudecoded_length_of, 1);
}
