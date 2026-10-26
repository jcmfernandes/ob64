# Ob64 gem

[![Gem Version](https://badge.fury.io/rb/ob64.svg)](http://rubygems.org/gems/ob64)
[![Build Status](https://github.com/jcmfernandes/ob64/workflows/Test/badge.svg?branch=master&event=push)](https://github.com/jcmfernandes/ob64/actions?query=workflow:Test)
[![Yard Docs](https://img.shields.io/badge/yard-docs-blue.svg)](http://www.rubydoc.info/gems/ob64/0.5.0)

A *fast* Base64 encoder and decoder as a Ruby gem.

How fast? Try it yourself, execute:

    $ rake benchmark

## Acknowledgements

The SIMD codecs (AVX2, AVX512, NEON64) derive from [aklomp/base64](https://github.com/aklomp/base64).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ob64'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ob64

Requires Ruby >= 3.3 and GCC or Clang. Linux on x86-64 and AArch64.

## Usage

```ruby
require "ob64"

bin1 = "This is data!"
string = Ob64.encode(bin1)
# string = "VGhpcyBpcyBkYXRhIQ=="

bin2 = Ob64.decode(string)
puts "Same? #{bin1 == bin2}"
# "Same? true"
```

Decode input with or without padding:

```ruby
Ob64.decode("VGhpcyBpcyBkYXRhIQ", loose: true)
```

Bad padding, non-zero trailing bits and non-alphabet characters still raise `ArgumentError`.

### Codec routing

SIMD codecs are used from a minimum input size, in bytes. Below it, plain C runs.

```ruby
Ob64.codec_routing
# x86-64 with AVX512 => {avx2: 128, avx512: 1280}
# x86-64 with AVX2   => {avx2: 128}
# AArch64            => {neon64: 128}
# other              => {}

Ob64.codec_routing = {avx2: 256, avx512: nil}
```

* Keys: `:avx2`, `:avx512`, `:neon64`. Value: smallest size at which the codec is used; `nil`: never.
* Routing applies only to `Ob64.*` and `m0`. Line-wrapped `m` and `u` always use plain C.
* Size is the input length when encoding, `input_length * 3 / 4` when decoding.
* The codec with the largest value <= size wins.
* The getter lists only codecs this CPU runs. The setter merges, and ignores known keys this CPU can't run.
* Raises `TypeError` for a non-Hash, `ArgumentError` for unknown keys, invalid values or equal values on two runnable codecs.

### `pack` / `unpack`

```ruby
require "ob64/core_ext"
```

Patches `Array#pack`, `String#unpack` and `String#unpack1`. Fast only for single-directive formats `m`, `mN`, `m*`, `u`, `uN`, `u*`. Everything else runs Ruby's own code. Passing `buffer:`, `offset:`, a block, or a non-String first element also runs Ruby's own code. Output is identical to Ruby's.

See [YARD documentation](http://www.rubydoc.info/gems/ob64).

## Releases

See [{file:CHANGELOG.md}](CHANGELOG.md).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jcmfernandes/ob64. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jcmfernandes/ob64/blob/master/CODE_OF_CONDUCT.md).

## TODO

* Streaming interface
* RFC 2045 (MIME) encoding/decoding
* Windows support

## License

Released under the MIT License. See [{file:LICENSE}](LICENSE).

Copyright (c) 2021, João Fernandes

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

### aklomp/base64

Released under the BSD 2-clause License. See [LICENSE](https://github.com/aklomp/base64/blob/master/LICENSE).

Copyright (c) 2005-2007, Nick Galbreath  
Copyright (c) 2013-2019, Alfred Klomp  
Copyright (c) 2015-2017, Wojciech Mula  
Copyright (c) 2016-2017, Matthieu Darbois  

## Code of Conduct

Everyone interacting in the Ob64 project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jcmfernandes/ob64/blob/master/CODE_OF_CONDUCT.md).
