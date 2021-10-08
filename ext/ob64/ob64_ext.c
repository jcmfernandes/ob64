#include <stdbool.h>
#include "ob64.h"

VALUE mOb64 = Qnil;
VALUE mOb64_LibBase64 = Qnil;
VALUE cOb64_LibBase64_EncodeState = Qnil;
VALUE cOb64_LibBase64_DecodeState = Qnil;

VALUE Ob64_encode_string(VALUE self, VALUE string);
VALUE Ob64_decode_string(VALUE self, VALUE string);
VALUE Ob64_decode_stream(VALUE self, VALUE string, VALUE decodeState, VALUE outbuf);
VALUE Ob64_encoded_length_of_string(VALUE self, VALUE string, VALUE withPadding);
VALUE Ob64_encoded_length_of_bytes(VALUE self, VALUE bytes, VALUE withPadding);
VALUE Ob64_decoded_length_of_string(VALUE self, VALUE string);
VALUE Ob64_decoded_length_of_bytes(VALUE self, VALUE bytes, VALUE padding);

size_t __encoded_length_of_string(VALUE string, bool withPadding);
size_t __encoded_length_of_bytes(size_t bytes, bool withPadding);
size_t __decoded_length_of_string(VALUE string, VALUE exception);
size_t __decoded_length_of_bytes(size_t bytes, size_t padding, VALUE exception);

static const rb_data_type_t Ob64_LibBase64_EncodeState_type = {
	.wrap_struct_name = "Ob64::LibBase64::EncodeState",
	.function = {
		.dfree = RUBY_DEFAULT_FREE,
	},
	.flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

VALUE Ob64_LibBase64_EncodeState_alloc(VALUE self)
{
  struct base64_state *state;
  VALUE obj = TypedData_Make_Struct(self, struct base64_state, &Ob64_LibBase64_EncodeState_type, state);
  base64_stream_encode_init(state, 0);
  return obj;
}

static const rb_data_type_t Ob64_LibBase64_DecodeState_type = {
	.wrap_struct_name = "Ob64::LibBase64::DecodeState",
	.function = {
		.dfree = RUBY_DEFAULT_FREE,
	},
	.flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

VALUE Ob64_LibBase64_DecodeState_alloc(VALUE self)
{
  struct base64_state *state;
  VALUE obj = TypedData_Make_Struct(self, struct base64_state, &Ob64_LibBase64_DecodeState_type, state);
  base64_stream_decode_init(state, 0);
  return obj;
}

void
Init_ob64_ext(void)
{
  mOb64 = rb_define_module("Ob64");
  mOb64_LibBase64 = rb_define_module_under(mOb64, "LibBase64");
  cOb64_LibBase64_DecodeState = rb_define_class_under(mOb64_LibBase64, "DecodeState", rb_cObject);
  rb_define_alloc_func(cOb64_LibBase64_DecodeState, Ob64_LibBase64_DecodeState_alloc);
  cOb64_LibBase64_EncodeState = rb_define_class_under(mOb64_LibBase64, "EncodeState", rb_cObject);
  rb_define_alloc_func(cOb64_LibBase64_EncodeState, Ob64_LibBase64_EncodeState_alloc);

  rb_define_private_method(mOb64_LibBase64, "__encode_string", Ob64_encode_string, 1);
  rb_define_private_method(mOb64_LibBase64, "__decode_string", Ob64_decode_string, 1);
  rb_define_private_method(mOb64_LibBase64, "__decode_stream", Ob64_decode_stream, 3);
  rb_define_private_method(mOb64_LibBase64, "__encoded_length_of_string", Ob64_encoded_length_of_string, 2);
  rb_define_private_method(mOb64_LibBase64, "__encoded_length_of_bytes", Ob64_encoded_length_of_bytes, 2);
  rb_define_private_method(mOb64_LibBase64, "__decoded_length_of_string", Ob64_decoded_length_of_string, 1);
  rb_define_private_method(mOb64_LibBase64, "__decoded_length_of_bytes", Ob64_decoded_length_of_bytes, 2);
}

VALUE Ob64_encode_string(VALUE self, VALUE string)
{
  VALUE result = rb_str_buf_new(__encoded_length_of_string(string, true));
  size_t nout;

  base64_encode(StringValuePtr(string), RSTRING_LEN(string), StringValuePtr(result), &nout, 0);
  rb_str_set_len(result, nout);

  return result;
}

VALUE Ob64_decode_stream(VALUE self, VALUE string, VALUE decodeState, VALUE outbuf)
{

  struct base64_state *state;
  TypedData_Get_Struct(decodeState, struct base64_state, &Ob64_LibBase64_DecodeState_type, state);

  size_t decoded_length = __decoded_length_of_string(string, rb_const_get(mOb64, rb_intern("DecodingError")));
  VALUE result;
  if (outbuf == Qnil) {
    result = rb_str_buf_new(decoded_length);
  } else {
    size_t outbuf_capacity = rb_str_capacity(outbuf);
    if (outbuf_capacity < decoded_length) {
      rb_str_modify_expand(outbuf, decoded_length - outbuf_capacity);
    }
    result = outbuf;
  }

  size_t nout;
  int ret = base64_stream_decode(state, StringValuePtr(string), RSTRING_LEN(string), StringValuePtr(result), &nout);
  if (ret == 0) {
    rb_raise(rb_const_get(mOb64, rb_intern("DecodingError")), "invalid base64");
  } else if (ret == -1) {
    rb_raise(rb_const_get(mOb64, rb_intern("UnsupportedCodecError")), "codec not found");
  }
  rb_str_set_len(result, nout);

  return result;
}

VALUE Ob64_decode_string(VALUE self, VALUE string)
{
  VALUE result = rb_str_buf_new(__decoded_length_of_string(string, rb_eArgError));
  size_t nout;

  if (!base64_decode(StringValuePtr(string), RSTRING_LEN(string), StringValuePtr(result), &nout, 0)) {
    rb_raise(rb_eArgError, "invalid base64");
  }
  rb_str_set_len(result, nout);

  return result;
}

VALUE Ob64_encoded_length_of_bytes(VALUE self, VALUE bytes, VALUE withPadding)
{
  return ULONG2NUM((unsigned long)__encoded_length_of_bytes(NUM2ULONG(bytes), withPadding != Qnil && withPadding != Qfalse ? true : false));
}

VALUE Ob64_encoded_length_of_string(VALUE self, VALUE string, VALUE withPadding)
{
  return ULONG2NUM((unsigned long)__encoded_length_of_string(string, withPadding != Qnil && withPadding != Qfalse ? true : false));
}

VALUE Ob64_decoded_length_of_bytes(VALUE self, VALUE bytes, VALUE padding)
{
  return ULONG2NUM((unsigned long)__decoded_length_of_bytes(NUM2ULONG(bytes), NUM2ULONG(padding), rb_eArgError));
}

VALUE Ob64_decoded_length_of_string(VALUE self, VALUE string)
{
  return ULONG2NUM((unsigned long)__decoded_length_of_string(string, rb_eArgError));
}

size_t __encoded_length_of_bytes(size_t bytes, bool withPadding)
{
  if (withPadding) {
    return (bytes + 2) / 3 * 4;
  } else {
    return ((bytes * 8) + 5) / 6;
  }
}

size_t __encoded_length_of_string(VALUE string, bool withPadding)
{
  return __encoded_length_of_bytes(RSTRING_LEN(string), withPadding);
}

size_t __decoded_length_of_bytes(size_t bytes, size_t padding, VALUE exception)
{
  if ((bytes - padding) % 4 == 1) {
    rb_raise(exception, "invalid base64");
  }

  return (3 * (bytes - padding)) / 4;
}

size_t __decoded_length_of_string(VALUE string, VALUE exception)
{
  size_t string_len = RSTRING_LEN(string);
  size_t padding = 0;
  if (string_len >= 2) {
    char *string_ptr = StringValuePtr(string);
    if (string_ptr[string_len - 1] == '=') padding++;
    if (string_ptr[string_len - 2] == '=') padding++;
  }

  return __decoded_length_of_bytes(RSTRING_LEN(string), padding, exception);
}
