# Ob64 gem

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

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ob64 project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jcmfernandes/ob64/blob/master/CODE_OF_CONDUCT.md).
