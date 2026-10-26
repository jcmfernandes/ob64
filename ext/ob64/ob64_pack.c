#include <limits.h>
#include <string.h>
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
  size_t n = 0;

  while (plen > 0) {
    long todo = plen > line_len ? line_len : plen;
    n += pack_uuencode_encode(src, (size_t)todo, out + n);
    src += todo;
    plen -= todo;
  }
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
  /* len * 3 / 4 without overflow */
  long cap = len / 4 * 3 + len % 4 * 3 / 4;
  /* +3: the decoder stores up to 3 bytes past a line's decoded length */
  VALUE buf = rb_str_buf_new(cap + 3);
  const unsigned char *s = (const unsigned char *)RSTRING_PTR(str);
  const unsigned char *send = s + len;
  char *ptr = RSTRING_PTR(buf);
  long total = 0;

  while (s < send && *s > ' ' && *s < 'a') {
    long line_len = (*s++ - ' ') & 077;

    total += line_len;
    if (total > cap) {
      line_len -= total - cap;
      total = cap;
    }

    if (line_len > 0) {
      long enc_bytes = (line_len + 2) / 3 * 4;
      long avail = 0;

      while (avail < enc_bytes && s + avail < send && s[avail] >= ' ' && s[avail] < 'a') {
        avail++;
      }

      if (avail == enc_bytes) {
        pack_uuencode_decode((const char *)s, (size_t)enc_bytes, ptr);
      }
      else {
        /* Missing or invalid chars decode as 0 */
        char encbuf[84];
        memcpy(encbuf, s, avail);
        memset(encbuf + avail, ' ', enc_bytes - avail);
        pack_uuencode_decode(encbuf, (size_t)enc_bytes, ptr);
      }
      s += avail;
      ptr += line_len;
    }

    if (s < send && *s != '\r' && *s != '\n') s++; /* possible checksum byte */
    if (s < send && *s == '\r') s++;
    if (s < send && *s == '\n') s++;
  }
  RB_GC_GUARD(str);

  rb_str_set_len(buf, total);

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
}
