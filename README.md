# Ob64 gem

[![Gem Version](https://badge.fury.io/rb/ob64.svg)](http://rubygems.org/gems/ob64)
[![Build Status](https://github.com/jcmfernandes/ob64/workflows/Test/badge.svg?branch=master&event=push)](https://github.com/jcmfernandes/ob64/actions?query=workflow:Test)
[![Yard Docs](https://img.shields.io/badge/yard-docs-blue.svg)](http://www.rubydoc.info/gems/ob64/0.5.0)

A *fast* Base64 encoder and decoder as a Ruby gem.

How fast? Try it yourself, execute:

    $ rake benchmark

When compared to Ruby's own `Base64` module, expect a 4x speedup in encoding, and a 2x speedup in decoding. YMMV.

## Acknowledgements

Ob64 uses `libbase64` under the hood. Originally developed by [aklomp](https://github.com/aklomp), here we started from [BurningEnlightenment](https://github.com/BurningEnlightenment)'s fork. `libbase64` takes advantage of SIMD (AVX2, NEON, AArch64/NEON, SSSE3, SSE4.1, SSE4.2, AVX) acceleration available on x86, x86-64, and ARM systems.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ob64'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ob64

Requires CMake and a C99 compiler.

**WARNING:** Only tested on Linux and x86-64.

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

If you want to replace Ruby's own `Base64` module with Ob64 **(NOT RECOMMENDED!)**:

```ruby
require "ob64/core_ext"
# It does NOT replace:
#   - Base64.encode64
#   - Base64.decode64
```

See [YARD documentation](http://www.rubydoc.info/gems/ob64).

## Releases

See [{file:CHANGELOG.md}](CHANGELOG.md).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jcmfernandes/ob64. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jcmfernandes/ob64/blob/master/CODE_OF_CONDUCT.md).

## TODO

* URL-safe encoding/decoding using separate alphabet/tables
* Streaming interface
* RFC 2045 (MIME) encoding/decoding
* Make the OpenMP threshold configurable (and enable OpenMP acceleration)
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

### libbase64

Released under the BSD 2-clause License. See [LICENSE](https://github.com/jcmfernandes/base64-cmake/blob/feature/cmake/LICENSE).

Copyright (c) 2005-2007, Nick Galbreath  
Copyright (c) 2013-2019, Alfred Klomp  
Copyright (c) 2015-2017, Wojciech Mula  
Copyright (c) 2016-2017, Matthieu Darbois  

## Code of Conduct

Everyone interacting in the Ob64 project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jcmfernandes/ob64/blob/master/CODE_OF_CONDUCT.md).
