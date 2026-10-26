#include <stdbool.h>
#include <stdint.h>
#include "ob64.h"
#include "ruby/thread_native.h"

VALUE mOb64 = Qnil;
VALUE mOb64_Ext = Qnil;

/* Indexed by enum pack_base64_codec */
static const char *const codec_names[PACK_BASE64_CODECS] = { "avx2", "avx512", "neon64" };
static ID codec_ids[PACK_BASE64_CODECS];
/* Serializes reads and updates of the codec routing */
static rb_nativethread_lock_t codec_routing_lock;

VALUE Ob64_encode_string(VALUE self, VALUE bin, VALUE urlsafe, VALUE padding);
VALUE Ob64_decode_string(VALUE self, VALUE string, VALUE urlsafe, VALUE loose);
VALUE Ob64_encoded_length_of(VALUE self, VALUE bin, VALUE withPadding);
VALUE Ob64_decoded_length_of(VALUE self, VALUE string);
VALUE Ob64_codec_routing(VALUE self);
VALUE Ob64_set_codec_routing(VALUE self, VALUE routing);

size_t __encoded_length_of(size_t bin_len, bool withPadding);
size_t __decoded_length_of(VALUE string);

void
Init_ob64_ext(void)
{
  rb_ext_ractor_safe(true);
  pack_base64_init();
  rb_nativethread_lock_initialize(&codec_routing_lock);
  for (int i = 0; i < PACK_BASE64_CODECS; i++) {
    codec_ids[i] = rb_intern(codec_names[i]);
  }

  mOb64 = rb_define_module("Ob64");
  mOb64_Ext = rb_define_module_under(mOb64, "Ext");

  rb_define_private_method(mOb64_Ext, "__encode", Ob64_encode_string, 3);
  rb_define_private_method(mOb64_Ext, "__decode", Ob64_decode_string, 3);
  rb_define_private_method(mOb64_Ext, "__encoded_length_of", Ob64_encoded_length_of, 2);
  rb_define_private_method(mOb64_Ext, "__decoded_length_of", Ob64_decoded_length_of, 1);
  rb_define_private_method(mOb64_Ext, "__codec_routing", Ob64_codec_routing, 0);
  rb_define_private_method(mOb64_Ext, "__set_codec_routing", Ob64_set_codec_routing, 1);
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

VALUE Ob64_codec_routing(VALUE self)
{
  size_t min_sizes[PACK_BASE64_CODECS];
  VALUE routing = rb_hash_new();

  rb_nativethread_lock_lock(&codec_routing_lock);
  for (int i = 0; i < PACK_BASE64_CODECS; i++) {
    min_sizes[i] = pack_base64_codec_min_size(i);
  }
  rb_nativethread_lock_unlock(&codec_routing_lock);

  for (int i = 0; i < PACK_BASE64_CODECS; i++) {
    if (pack_base64_codec_runnable(i)) {
      rb_hash_aset(routing, ID2SYM(codec_ids[i]), min_sizes[i] == SIZE_MAX ? Qnil : SIZET2NUM(min_sizes[i]));
    }
  }

  return routing;
}

struct codec_routing_update {
  bool given[PACK_BASE64_CODECS];
  size_t min_sizes[PACK_BASE64_CODECS];
};

static int codec_routing_update_i(VALUE key, VALUE value, VALUE arg)
{
  struct codec_routing_update *update = (struct codec_routing_update *)arg;
  int codec = -1;
  size_t min_size = SIZE_MAX;

  for (int i = 0; i < PACK_BASE64_CODECS; i++) {
    if (key == ID2SYM(codec_ids[i])) codec = i;
  }
  if (codec < 0) {
    rb_raise(rb_eArgError, "unknown codec: %+"PRIsVALUE, key);
  }

  if (!NIL_P(value)) {
    int sign = RB_INTEGER_TYPE_P(value) ? rb_integer_pack(value, &min_size, 1, sizeof(min_size), 0, INTEGER_PACK_NATIVE_BYTE_ORDER) : -1;
    if ((sign != 0 && sign != 1) || min_size == SIZE_MAX) {
      rb_raise(rb_eArgError, "invalid size for %s: %+"PRIsVALUE, codec_names[codec], value);
    }
  }

  update->given[codec] = true;
  update->min_sizes[codec] = min_size;

  return ST_CONTINUE;
}

VALUE Ob64_set_codec_routing(VALUE self, VALUE routing)
{
  struct codec_routing_update update = { { false }, { 0 } };
  size_t merged[PACK_BASE64_CODECS];
  int clash_a = -1, clash_b = -1;

  Check_Type(routing, T_HASH);
  rb_hash_foreach(routing, codec_routing_update_i, (VALUE)&update);

  /* No raising while locked */
  rb_nativethread_lock_lock(&codec_routing_lock);
  for (int i = 0; i < PACK_BASE64_CODECS; i++) {
    merged[i] = update.given[i] ? update.min_sizes[i] : pack_base64_codec_min_size(i);
  }
  for (int i = 0; i < PACK_BASE64_CODECS && clash_a < 0; i++) {
    for (int j = i + 1; j < PACK_BASE64_CODECS && clash_a < 0; j++) {
      if (merged[i] != SIZE_MAX && merged[i] == merged[j] &&
          pack_base64_codec_runnable(i) && pack_base64_codec_runnable(j)) {
        clash_a = i;
        clash_b = j;
      }
    }
  }
  if (clash_a < 0) {
    for (int i = 0; i < PACK_BASE64_CODECS; i++) {
      if (update.given[i]) pack_base64_set_codec_min_size(i, update.min_sizes[i]);
    }
  }
  rb_nativethread_lock_unlock(&codec_routing_lock);

  if (clash_a >= 0) {
    rb_raise(rb_eArgError, "%s and %s have the same size: %"PRIuSIZE, codec_names[clash_a], codec_names[clash_b], merged[clash_a]);
  }

  return routing;
}
