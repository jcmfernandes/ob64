#include <stdbool.h>
#include "ob64.h"

VALUE mOb64 = Qnil;
VALUE mOb64_Ext = Qnil;

/* Indexed by enum pack_codec */
static const char *const codec_names[PACK_CODECS] = { "scalar", "avx2", "avx512", "neon64" };
static ID codec_ids[PACK_CODECS];

VALUE Ob64_encode_string(VALUE self, VALUE bin, VALUE urlsafe, VALUE padding);
VALUE Ob64_decode_string(VALUE self, VALUE string, VALUE urlsafe, VALUE loose);
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
  RB_GC_GUARD(bin);

  return result;
}

VALUE Ob64_decode_string(VALUE self, VALUE string, VALUE urlsafe, VALUE loose)
{
  StringValue(string);
  size_t string_len = RSTRING_LEN(string);
  /* Room for unpadded input */
  VALUE result = rb_str_buf_new((string_len + 3) / 4 * 3);
  int flags = (RTEST(urlsafe) ? PACK_BASE64_URL_SAFE : 0) | (RTEST(loose) ? PACK_BASE64_LOOSE : 0);
  size_t nout;

  if (!pack_base64_decode(RSTRING_PTR(string), string_len, RSTRING_PTR(result), &nout, flags)) {
    rb_raise(rb_eArgError, "invalid base64");
  }
  rb_str_set_len(result, nout);
  RB_GC_GUARD(string);

  return result;
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
