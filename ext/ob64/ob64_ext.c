#include <stdbool.h>
#include "ob64.h"

VALUE mOb64 = Qnil;
VALUE mOb64_LibBase64 = Qnil;

VALUE Ob64_encode_string(VALUE self, VALUE bin);
VALUE Ob64_decode_string(VALUE self, VALUE string);
VALUE Ob64_encoded_length_of(VALUE self, VALUE bin, VALUE withPadding);
VALUE Ob64_decoded_length_of(VALUE self, VALUE string);

size_t __encoded_length_of(VALUE string, bool withPadding);
size_t __decoded_length_of(VALUE string);

void
Init_ob64_ext(void)
{
  mOb64 = rb_define_module("Ob64");
  mOb64_LibBase64 = rb_define_module_under(mOb64, "LibBase64");

  rb_define_private_method(mOb64_LibBase64, "__encode", Ob64_encode_string, 1);
  rb_define_private_method(mOb64_LibBase64, "__decode", Ob64_decode_string, 1);
  rb_define_private_method(mOb64_LibBase64, "__encoded_length_of", Ob64_encoded_length_of, 2);
  rb_define_private_method(mOb64_LibBase64, "__decoded_length_of", Ob64_decoded_length_of, 1);
}

VALUE Ob64_encode_string(VALUE self, VALUE bin)
{
  VALUE result = rb_str_buf_new(__encoded_length_of(bin, true));
  size_t nout;

  base64_encode(StringValuePtr(bin), RSTRING_LEN(bin), StringValuePtr(result), &nout, 0);
  rb_str_set_len(result, nout);

  return result;
}

VALUE Ob64_decode_string(VALUE self, VALUE string)
{
  VALUE result = rb_str_buf_new(__decoded_length_of(string));
  size_t nout;

  if (!base64_decode(StringValuePtr(string), RSTRING_LEN(string), StringValuePtr(result), &nout, 0)) {
    rb_raise(rb_eArgError, "invalid base64");
  }
  rb_str_set_len(result, nout);

  return result;
}

VALUE Ob64_encoded_length_of(VALUE self, VALUE bin, VALUE withPadding)
{
  return ULONG2NUM((unsigned long)__encoded_length_of(bin, withPadding != Qnil && withPadding != Qfalse ? true : false));
}

VALUE Ob64_decoded_length_of(VALUE self, VALUE string)
{
  return ULONG2NUM((unsigned long)__decoded_length_of(string));
}

size_t __encoded_length_of(VALUE bin, bool withPadding)
{
  if (withPadding) {
    return (RSTRING_LEN(bin) + 2) / 3 * 4;
  } else {
    return ((RSTRING_LEN(bin) * 8) + 5) / 6;
  }
}

size_t __decoded_length_of(VALUE string)
{
  char *string_ptr = StringValuePtr(string);
  size_t string_len = RSTRING_LEN(string);
  size_t padding = 0;
  if (string_ptr[string_len - 1] == '=') padding++;
  if (string_ptr[string_len - 2] == '=') padding++;

  if ((string_len - padding) % 4 == 1) {
    rb_raise(rb_eArgError, "invalid base64");
  }

  return (3 * (string_len - padding)) / 4;
}
