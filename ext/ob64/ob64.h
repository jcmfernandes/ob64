#ifndef OB64_H
#define OB64_H 1

#include "pack_base64.h"
#include "ruby.h"

void Init_ob64_pack(VALUE mExt);
long ob64_src_range(VALUE dst, VALUE src, long off, VALUE len);
void ob64_check_encode_len(size_t len);
char *ob64_reserve(VALUE dst, long n);
void ob64_encode_append(VALUE dst, VALUE src, long off, long len, VALUE urlsafe, VALUE padding);

#endif /* OB64_H */
