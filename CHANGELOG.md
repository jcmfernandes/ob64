## [Unreleased]

- **Breaking:** `ob64/core_ext` patches `Array#pack`, `String#unpack` and `String#unpack1` instead of `Base64`.
- **Breaking:** Require Ruby >= 3.3.
- **Breaking:** Drop CMake and libbase64. Require GCC or Clang.
- **Breaking:** Base64 methods move from `Ob64` to `Ob64::Base64` (e.g. `Ob64.encode` is now `Ob64::Base64.encode`).
- **Breaking:** `decode` and `urlsafe_decode` reject non-zero trailing bits (e.g. `"AB=="`), like `unpack1("m0")`.
- Port SIMD codecs (AVX2, AVX512, NEON64) into the extension.
- Add `Ob64.codec_routing` and `Ob64.codec_routing=`.
- Add `Ob64::Base64.decode(string, loose: true)`.
- Add `Ob64::UU.encode`, `Ob64::UU.decode`, `Ob64::UU.encoded_length_of` and `Ob64::UU.decoded_length_of`.
- Encode and decode URL-safe in C.
- Support Linux on AArch64.

# [0.5.0] - 2021-09-29

- Ignore all previous versions as they weren't including libbase64 (:

# [0.4.0] - 2021-09-28

- Detail gemspec. Ignore.

## [0.3.0] - 2021-09-28

- Raise error when attempting to get the base64-decoded length of an invalid (in
  length) base64-encoded payload.

## [0.2.0] - 2021-09-26

- Add yard documention

## [0.1.0] - 2021-09-25

- Initial release
