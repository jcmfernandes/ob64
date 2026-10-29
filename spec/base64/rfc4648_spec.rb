# frozen_string_literal: true

RSpec.describe "Base64 RFC 4648, strict" do
  include VariantHelpers

  # Bytes => encoding
  encodings = {
    "" => "",
    "\0" => "AA==",
    "\0\0" => "AAA=",
    "\0\0\0" => "AAAA",
    "\0\0\0\0" => "AAAAAA==",
    "\xFF" => "/w==",
    "\xFF\xFF" => "//8=",
    "\xFF\xFF\xFF" => "////",
    "\xFF\xFF\xFF\xFF\xFF" => "//////8=",
    "\xFF\xFF\xFF\xFF\xFF\xFF" => "////////",
    "\xFF\xFF\xFF\xFF\xFF\xFF\xFF" => "/////////w==",
    "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xEF" => "///////////v",
    "\xFB\xFF\xBF" => "+/+/",
    "Send reinforcements" => "U2VuZCByZWluZm9yY2VtZW50cw==",
    "Now is the time for all good coders\nto learn Ruby" =>
      "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ==",
    "This is line one\nThis is line two\nThis is line three\nAnd so on...\n" =>
      "VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K"
  }.to_h { |bin, string| [bin.b.freeze, string] }.freeze

  # Rejected: bad length or padding, non-zero trailing bits, non-alphabet characters
  invalid = [
    "A", "AA", "AAA", "AAAAA", "AAAAAA", "//////8", "/////////w",
    "AA=", "AAA==", "AAAA=", "A===", "====", "AA=A", "AA==AA", "=AAA",
    "=", "a=", "a=Gk", "aG=k", "=aGk=", "==aGk=", "=aGVsbG8=", "a=GVsbG8=", "aGk=\n=aGk=", "aGVs\n=bG8=",
    "AB==", "AAB=",
    "AA\nAA", "AAAA\n", "AA AA", "AA-_", "^AAA", "AAA^", "AA\0A", "AA\xFFA"
  ].map { |string| string.b.freeze }.freeze

  def ruby_encode(bin) = NATIVE_PACK.bind_call([bin], "m0")

  def ruby_decode(string) = NATIVE_UNPACK1.bind_call(string, "m0")

  # Compares decode and unpack with Ruby's
  def check_decode(mismatches, label, string, formats = %w[m0])
    check(mismatches, "decode(#{label})", outcome { ruby_decode(string) },
      outcome { Ob64::Base64::RFC4648.decode(string) })
    check_unpack(mismatches, label, string, formats)
  end

  # Compares reading string through a Reader with Ruby's and decode
  def check_reader(mismatches, label, string)
    actual = outcome { read_all(string) { |io| Ob64::Base64::RFC4648::Reader.new(io) } }
    check(mismatches, "Reader(#{label})", outcome { ruby_decode(string) }, actual)
    check(mismatches, "Reader(#{label}) vs decode", outcome { Ob64::Base64::RFC4648.decode(string) }, actual)
  end

  def valid_inputs(size) = [ruby_encode(rng.bytes(size))]

  def broken_inputs(size)
    broken(ruby_encode(rng.bytes(size)), ["=", "\n", "\r", " ", "+", "/", "-", "_", "A", "\0", "\xFF"])
  end

  def garbage_inputs(size)
    alphabet = [*"A".."Z", *"a".."z", *"0".."9", "+", "/", "=", "\n"]
    uu_alphabet = [*" ".."`", "\n"]
    [
      rng.bytes(size),
      Array.new(size) { alphabet.sample(random: rng) }.join.b,
      Array.new(size) { uu_alphabet.sample(random: rng) }.join.b,
      NATIVE_PACK.bind_call([rng.bytes(size)], "u")
    ]
  end

  each_codec do
    describe "fixed cases" do
      it "encodes" do
        encodings.each do |bin, string|
          expect(ruby_encode(bin)).to eq(string), bin.inspect
          expect(Ob64::Base64::RFC4648.encode(bin)).to eq(string)
          expect(Ob64::Base64::RFC4648.encode(bin).encoding).to eq(Encoding::US_ASCII)
          expect(Ob64::Base64::RFC4648.encoded_length_of(bin)).to eq(string.bytesize)
          expect([bin].pack("m0")).to eq(string)
          expect([bin].pack("m0").encoding).to eq(Encoding::US_ASCII)
        end
      end

      it "decodes" do
        encodings.each do |bin, string|
          expect(ruby_decode(string)).to eq(bin), string.inspect
          expect(Ob64::Base64::RFC4648.decode(string)).to eq(bin)
          expect(Ob64::Base64::RFC4648.decode(string).encoding).to eq(Encoding::BINARY)
          expect(Ob64::Base64::RFC4648.decoded_length_of(string)).to eq(bin.bytesize)
          expect(string.unpack1("m0")).to eq(bin)
          expect(string.unpack("m0")).to eq([bin])
        end
      end

      it "rejects invalid input" do
        invalid.each do |string|
          expect { ruby_decode(string) }.to raise_error(ArgumentError, "invalid base64"), string.inspect
          expect { Ob64::Base64::RFC4648.decode(string) }.to raise_error(ArgumentError, "invalid base64"), string.inspect
          expect { string.unpack1("m0") }.to raise_error(ArgumentError, "invalid base64"), string.inspect
          expect { string.unpack("m0") }.to raise_error(ArgumentError, "invalid base64"), string.inspect
        end
        %w[A AAAAA AAAAA==].each do |string|
          expect { Ob64::Base64::RFC4648.decoded_length_of(string) }.to raise_error(ArgumentError, "invalid base64")
        end
      end

      it "rejects bad arguments" do
        %i[encode decode encoded_length_of decoded_length_of].each do |method|
          expect { Ob64::Base64::RFC4648.public_send(method, 1) }
            .to raise_error(TypeError, "no implicit conversion of Integer into String")
        end
      end
    end

    describe "random cases" do
      it "encodes" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          string = ruby_encode(bin)
          check(mismatches, "encode(#{size})", outcome { string }, outcome { Ob64::Base64::RFC4648.encode(bin) })
          check(mismatches, "encoded_length_of(#{size})", string.bytesize, Ob64::Base64::RFC4648.encoded_length_of(bin))
          check(mismatches, "pack(#{size})", outcome { ruby_encode(bin) }, outcome { [bin].pack("m0") })
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes valid input" do
        mismatches = []
        sizes.each do |size|
          string = ruby_encode(rng.bytes(size))
          check_decode(mismatches, "#{size} bytes", string, %w[m0 m0000000000])
          check(mismatches, "decoded_length_of(#{size})", size, Ob64::Base64::RFC4648.decoded_length_of(string))
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes broken input like Ruby" do
        mismatches = []
        sizes.each do |size|
          broken_inputs(size).each { |string| check_decode(mismatches, string.inspect[0, 100], string) }
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes garbage like Ruby" do
        mismatches = []
        sizes.each do |size|
          garbage_inputs(size).each do |string|
            check_decode(mismatches, "#{size} bytes: #{string.inspect[0, 60]}", string)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes any byte at fixed positions like Ruby" do
        mismatches = []
        {"valid" => [ruby_encode(rng.bytes(192)).b, []], "A * 256" => [("A" * 256).b, [100]]}
          .each do |name, (base, extra)|
            sweep_positions(base, *extra).each do |position|
              (0..255).each do |byte|
                string = base.dup
                string.setbyte(position, byte)
                check_decode(mismatches, "byte #{byte} at #{position} of #{name}", string)
              end
            end
          end
        expect_no_mismatches(mismatches)
      end
    end

    describe "streams" do
      it "Writer encodes like encode" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          actual = write_all(bin) { |io| Ob64::Base64::RFC4648::Writer.new(io) }
          check(mismatches, "Writer(#{size})", ruby_encode(bin), actual)
          check(mismatches, "Writer(#{size}) vs encode", Ob64::Base64::RFC4648.encode(bin), actual)
        end
        expect_no_mismatches(mismatches)
      end

      it "Reader decodes valid input like decode" do
        mismatches = []
        sizes.each do |size|
          valid_inputs(size).each { |string| check_reader(mismatches, "#{size} bytes, #{string.bytesize} chars", string) }
        end
        expect_no_mismatches(mismatches)
      end

      it "Reader decodes broken input like decode" do
        mismatches = []
        sizes.each do |size|
          broken_inputs(size).each { |string| check_reader(mismatches, string.inspect[0, 100], string) }
        end
        expect_no_mismatches(mismatches)
      end

      it "Reader decodes garbage like decode" do
        mismatches = []
        sizes.each do |size|
          garbage_inputs(size).each do |string|
            check_reader(mismatches, "#{size} bytes: #{string.inspect[0, 60]}", string)
          end
        end
        expect_no_mismatches(mismatches)
      end
    end
  end
end
