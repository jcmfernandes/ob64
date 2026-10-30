#ifndef OB64_H
#define OB64_H 1

#include "pack_base64.h"
#include "ruby.h"

void Init_ob64_pack(VALUE mExt);
long ob64_src_len(VALUE dst, VALUE src, VALUE len);
char *ob64_reserve(VALUE dst, long n);

#endif /* OB64_H */
