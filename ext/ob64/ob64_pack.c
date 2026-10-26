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

/* Sets res's length to n and makes it a US-ASCII String, as native pack does */
static VALUE
ascii_result(VALUE res, size_t n)
{
  rb_str_set_len(res, (long)n);
  ENCODING_CODERANGE_SET(res, rb_usascii_encindex(), ENC_CODERANGE_7BIT);

  return res;
}

static VALUE
uuencode(VALUE from, long line_len)
{
  long plen = RSTRING_LEN(from);
  /* A length byte and a newline per line */
  long lines = (plen + line_len - 1) / line_len;
  VALUE res = rb_str_buf_new((plen + 2) / 3 * 4 + lines * 2);
  const char *src = RSTRING_PTR(from);
  char *out = RSTRING_PTR(res);
  size_t n = pack_uuencode_lines(src, (size_t)plen, out, (size_t)line_len);
  RB_GC_GUARD(from);

  return ascii_result(res, n);
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

  VALUE res;
  size_t n;

  if (type == 'm' && count == 0) {
    res = rb_str_buf_new((plen + 2) / 3 * 4);
    n = pack_base64_encode(RSTRING_PTR(from), (size_t)plen, RSTRING_PTR(res), 0);
  }
  else {
    long len = count;

    /* '*' gets 45, as natively */
    if (len <= 2) len = 45;
    else if (len > 63 && type == 'u') len = 63;
    else len = len / 3 * 3;

    if (type == 'u') return uuencode(from, len);

    /* A newline per line */
    long lines = (plen + len - 1) / len;
    res = rb_str_buf_new((plen + 2) / 3 * 4 + lines);
    n = pack_base64_encode_rfc2045(RSTRING_PTR(from), (size_t)plen, RSTRING_PTR(res), (int)len);
  }
  RB_GC_GUARD(from);

  return ascii_result(res, n);
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

static VALUE
Ob64_uuencode(VALUE self, VALUE bin)
{
  StringValue(bin);

  return uuencode(bin, 45);
}

static VALUE
Ob64_uudecode(VALUE self, VALUE string)
{
  StringValue(string);

  return uudecode(string);
}

static VALUE
Ob64_uuencoded_length_of(VALUE self, VALUE bin)
{
  StringValue(bin);
  long plen = RSTRING_LEN(bin);
  /* Per line: a length byte, 4 chars per 3 bytes and a newline */
  long full = plen / 45, rest = plen % 45;

  return LONG2NUM(full * 62 + (rest ? (rest + 2) / 3 * 4 + 2 : 0));
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

  rb_define_private_method(mExt, "__uuencode", Ob64_uuencode, 1);
  rb_define_private_method(mExt, "__uudecode", Ob64_uudecode, 1);
  rb_define_private_method(mExt, "__uuencoded_length_of", Ob64_uuencoded_length_of, 1);
  rb_define_private_method(mExt, "__uudecoded_length_of", Ob64_uudecoded_length_of, 1);
}
