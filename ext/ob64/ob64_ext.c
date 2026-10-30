#include <stdbool.h>
#include "ob64.h"
#include "ruby/encoding.h"

VALUE mOb64 = Qnil;
VALUE mOb64_Ext = Qnil;

/* Indexed by enum pack_codec */
static const char *const codec_names[PACK_CODECS] = { "scalar", "avx2", "avx512", "neon64" };
static ID codec_ids[PACK_CODECS];

VALUE Ob64_encode_string(VALUE self, VALUE bin, VALUE urlsafe, VALUE padding);
VALUE Ob64_decode_string(VALUE self, VALUE string, VALUE urlsafe, VALUE loose);
VALUE Ob64_decode_into(VALUE self, VALUE dst, VALUE src, VALUE len, VALUE urlsafe, VALUE loose);
VALUE Ob64_consume(VALUE self, VALUE str, VALUE n);
VALUE Ob64_copy_into(VALUE self, VALUE dst, VALUE src, VALUE off, VALUE n);
VALUE Ob64_encoded_length_of(VALUE self, VALUE bin, VALUE withPadding);
VALUE Ob64_decoded_length_of(VALUE self, VALUE string);
VALUE Ob64_codec(VALUE self);
VALUE Ob64_set_codec(VALUE self, VALUE codec);
VALUE Ob64_codecs(VALUE self);

size_t __encoded_length_of(size_t bin_len, bool withPadding);
size_t __decoded_length_of(VALUE string);

void
Init_ob64_ext(void)
{
  rb_ext_ractor_safe(true);
  pack_base64_init();
  for (int i = 0; i < PACK_CODECS; i++) {
    codec_ids[i] = rb_intern(codec_names[i]);
  }

  mOb64 = rb_define_module("Ob64");
  mOb64_Ext = rb_define_module_under(mOb64, "Ext");

  rb_define_private_method(mOb64_Ext, "__encode", Ob64_encode_string, 3);
  rb_define_private_method(mOb64_Ext, "__decode", Ob64_decode_string, 3);
  rb_define_private_method(mOb64_Ext, "__decode_into", Ob64_decode_into, 5);
  rb_define_private_method(mOb64_Ext, "__consume", Ob64_consume, 2);
  rb_define_private_method(mOb64_Ext, "__copy_into", Ob64_copy_into, 4);
  rb_define_private_method(mOb64_Ext, "__encoded_length_of", Ob64_encoded_length_of, 2);
  rb_define_private_method(mOb64_Ext, "__decoded_length_of", Ob64_decoded_length_of, 1);
  rb_define_private_method(mOb64_Ext, "__codec", Ob64_codec, 0);
  rb_define_private_method(mOb64_Ext, "__set_codec", Ob64_set_codec, 1);
  rb_define_private_method(mOb64_Ext, "__codecs", Ob64_codecs, 0);

  Init_ob64_pack(mOb64_Ext);
}

VALUE Ob64_encode_string(VALUE self, VALUE bin, VALUE urlsafe, VALUE padding)
{
  StringValue(bin);
  size_t bin_len = RSTRING_LEN(bin);
  VALUE result = rb_str_buf_new(__encoded_length_of(bin_len, true));
  int flags = RTEST(urlsafe) ? PACK_BASE64_URL_SAFE : 0;

  pack_base64_encode(RSTRING_PTR(bin), bin_len, RSTRING_PTR(result), flags);
  rb_str_set_len(result, __encoded_length_of(bin_len, RTEST(padding)));
  /* US-ASCII, as pack("m0") */
  ENCODING_CODERANGE_SET(result, rb_usascii_encindex(), ENC_CODERANGE_7BIT);
  RB_GC_GUARD(bin);

  return result;
}

/* Validates the _into arguments; returns len, a length of src's prefix */
long ob64_src_len(VALUE dst, VALUE src, VALUE len)
{
  long n = NUM2LONG(len);

  if (dst == src) rb_raise(rb_eArgError, "dst and src must differ");
  if (n < 0 || n > RSTRING_LEN(src)) rb_raise(rb_eArgError, "length out of range: %ld", n);

  return n;
}

/*
 * Makes dst modifiable with room for n more bytes past its length; returns
 * where they go. Keeps a large enough capacity, as expanding reallocates.
 */
char *ob64_reserve(VALUE dst, long n)
{
  long len = RSTRING_LEN(dst);

  if ((size_t)n > rb_str_capacity(dst) - (size_t)len) {
    rb_str_modify_expand(dst, n);
  }
  else {
    rb_str_modify(dst);
  }

  return RSTRING_PTR(dst) + len;
}

/* Appends the decode of src[0, len] to dst; on invalid input raises, dst unchanged */
static void
decode_append(VALUE dst, VALUE src, long len, VALUE urlsafe, VALUE loose)
{
  long dst_len = RSTRING_LEN(dst);
  /* Room for unpadded input */
  char *out = ob64_reserve(dst, len / 4 * 3 + (len % 4 ? 3 : 0));
  int flags = (RTEST(urlsafe) ? PACK_BASE64_URL_SAFE : 0) | (RTEST(loose) ? PACK_BASE64_LOOSE : 0);
  size_t nout;

  if (!pack_base64_decode(RSTRING_PTR(src), (size_t)len, out, &nout, flags)) {
    /* Restores the terminator */
    rb_str_set_len(dst, dst_len);
    rb_raise(rb_eArgError, "invalid base64");
  }
  rb_str_set_len(dst, dst_len + (long)nout);
  RB_GC_GUARD(src);
}

VALUE Ob64_decode_string(VALUE self, VALUE string, VALUE urlsafe, VALUE loose)
{
  StringValue(string);
  VALUE result = rb_str_buf_new(0);

  decode_append(result, string, RSTRING_LEN(string), urlsafe, loose);

  return result;
}

VALUE Ob64_decode_into(VALUE self, VALUE dst, VALUE src, VALUE len, VALUE urlsafe, VALUE loose)
{
  StringValue(dst);
  StringValue(src);
  decode_append(dst, src, ob64_src_len(dst, src, len), urlsafe, loose);
  RB_GC_GUARD(dst);

  return dst;
}

/* Drops str's first n bytes */
VALUE Ob64_consume(VALUE self, VALUE str, VALUE n)
{
  StringValue(str);
  long c = NUM2LONG(n);
  long len = RSTRING_LEN(str);

  if (c < 0 || c > len) rb_raise(rb_eArgError, "length out of range: %ld", c);
  rb_str_modify(str);
  memmove(RSTRING_PTR(str), RSTRING_PTR(str) + c, (size_t)(len - c));
  rb_str_set_len(str, len - c);
  RB_GC_GUARD(str);

  return str;
}

/* Replaces dst's content with src[off, n] */
VALUE Ob64_copy_into(VALUE self, VALUE dst, VALUE src, VALUE off, VALUE n)
{
  StringValue(dst);
  StringValue(src);
  long o = NUM2LONG(off);
  long c = NUM2LONG(n);

  if (dst == src) rb_raise(rb_eArgError, "dst and src must differ");
  if (o < 0 || o > RSTRING_LEN(src)) rb_raise(rb_eArgError, "offset out of range: %ld", o);
  if (c < 0 || c > RSTRING_LEN(src) - o) rb_raise(rb_eArgError, "length out of range: %ld", c);
  /* Independent before setting the length */
  rb_str_modify(dst);
  rb_str_set_len(dst, 0);
  memcpy(ob64_reserve(dst, c), RSTRING_PTR(src) + o, (size_t)c);
  rb_str_set_len(dst, c);
  RB_GC_GUARD(dst);
  RB_GC_GUARD(src);

  return dst;
}

VALUE Ob64_encoded_length_of(VALUE self, VALUE bin, VALUE withPadding)
{
  StringValue(bin);
  return ULONG2NUM((unsigned long)__encoded_length_of(RSTRING_LEN(bin), RTEST(withPadding)));
}

VALUE Ob64_decoded_length_of(VALUE self, VALUE string)
{
  return ULONG2NUM((unsigned long)__decoded_length_of(string));
}

size_t __encoded_length_of(size_t bin_len, bool withPadding)
{
  if (withPadding) {
    return (bin_len + 2) / 3 * 4;
  } else {
    return ((bin_len * 8) + 5) / 6;
  }
}

size_t __decoded_length_of(VALUE string)
{
  char *string_ptr = StringValuePtr(string);
  size_t string_len = RSTRING_LEN(string);
  size_t padding = 0;
  if (string_len >= 1 && string_ptr[string_len - 1] == '=') padding++;
  if (string_len >= 2 && string_ptr[string_len - 2] == '=') padding++;

  if ((string_len - padding) % 4 == 1) {
    rb_raise(rb_eArgError, "invalid base64");
  }

  return (3 * (string_len - padding)) / 4;
}

VALUE Ob64_codec(VALUE self)
{
  return ID2SYM(codec_ids[pack_codec_current()]);
}

VALUE Ob64_set_codec(VALUE self, VALUE codec)
{
  for (int i = 0; i < PACK_CODECS; i++) {
    if (codec == ID2SYM(codec_ids[i])) {
      if (!pack_codec_runnable(i)) {
        rb_raise(rb_eArgError, "%s is not supported by this CPU", codec_names[i]);
      }
      pack_codec_set(i);
      return codec;
    }
  }
  rb_raise(rb_eArgError, "unknown codec: %+"PRIsVALUE, codec);
}

VALUE Ob64_codecs(VALUE self)
{
  VALUE codecs = rb_ary_new();

  for (int i = 0; i < PACK_CODECS; i++) {
    if (pack_codec_runnable(i)) rb_ary_push(codecs, ID2SYM(codec_ids[i]));
  }

  return codecs;
}
