# Ob64 gem

[![Gem Version](https://badge.fury.io/rb/ob64.svg)](http://rubygems.org/gems/ob64)
[![CI](https://github.com/jcmfernandes/ob64/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/jcmfernandes/ob64/actions/workflows/main.yml)
[![Yard Docs](https://img.shields.io/badge/yard-docs-blue.svg)](http://www.rubydoc.info/gems/ob64/0.6.0)

A *fast* Base64 and uuencode encoder and decoder as a Ruby gem.

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
```

### Base64

```ruby
bin1 = "This is data!"
string = Ob64::Base64.encode(bin1)
# string = "VGhpcyBpcyBkYXRhIQ=="

bin2 = Ob64::Base64.decode(string)
puts "Same? #{bin1 == bin2}"
# "Same? true"
```

Decode input with or without padding:

```ruby
Ob64::Base64.decode("VGhpcyBpcyBkYXRhIQ", loose: true)
```

Bad padding, non-zero trailing bits and non-alphabet characters still raise `ArgumentError`.

URL-safe alphabet: `Ob64::Base64.urlsafe_encode(bin, padding: false)`, `Ob64::Base64.urlsafe_decode(string)`.

### uuencode

Same output as `pack("u")` / `unpack1("u")`:

```ruby
string = Ob64::UU.encode("This is data!")
# string = "-5&AI<R!I<R!D871A(0``\n"

Ob64::UU.decode(string)
# "This is data!"
```

### Codecs

The best codec this CPU runs is picked at load and used for every call. `Ob64.codec=` forces one for the whole process (e.g. `:scalar`, plain C).

```ruby
Ob64.codecs
# x86-64 with AVX512 => [:scalar, :avx2, :avx512]
# x86-64 with AVX2   => [:scalar, :avx2]
# AArch64            => [:scalar, :neon64]
# other              => [:scalar]

Ob64.best_codec     # => :avx512
Ob64.codec          # => :avx512
Ob64.codec = :scalar
Ob64.codec = Ob64.best_codec
```

AVX512 needs VL, VBMI and VBMI2.

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
