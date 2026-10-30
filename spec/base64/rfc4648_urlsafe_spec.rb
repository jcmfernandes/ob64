# frozen_string_literal: true

RSpec.describe "Base64 RFC 4648, URL-safe" do
  include VariantHelpers

  # Bytes => [padded, unpadded]
  encodings = {
    "" => ["", ""],
    "\0" => ["AA==", "AA"],
    "\0\0" => ["AAA=", "AAA"],
    "\0\0\0" => ["AAAA", "AAAA"],
    "\0\0\0\0" => ["AAAAAA==", "AAAAAA"],
    "\xFF" => ["_w==", "_w"],
    "\xFF\xFF" => ["__8=", "__8"],
    "\xFF\xFF\xFF" => ["____", "____"],
    "\xFF\xFF\xFF\xFF\xFF" => ["______8=", "______8"],
    "\xFF\xFF\xFF\xFF\xFF\xFF" => ["________", "________"],
    "\xFF\xFF\xFF\xFF\xFF\xFF\xFF" => ["_________w==", "_________w"],
    "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xEF" => ["___________v", "___________v"],
    "\xFB\xFF\xBF" => ["-_-_", "-_-_"],
    "\xFB" => ["-w==", "-w"],
    "\xFB\xEF" => ["--8=", "--8"],
    "Send reinforcements" => ["U2VuZCByZWluZm9yY2VtZW50cw==", "U2VuZCByZWluZm9yY2VtZW50cw"],
    "Now is the time for all good coders\nto learn Ruby" =>
      ["Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ==",
        "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ"],
    "This is line one\nThis is line two\nThis is line three\nAnd so on...\n" =>
      ["VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K",
        "VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K"]
  }.to_h { |bin, strings| [bin.b.freeze, strings.freeze] }.freeze

  # Also accepted: unpadded, and the standard alphabet (alone or mixed)
  more_decodings = {
    "AA" => "\0",
    "AAA" => "\0\0",
    "_w" => "\xFF",
    "__8" => "\xFF\xFF",
    "+/+/" => "\xFB\xFF\xBF",
    "+w==" => "\xFB",
    "+w" => "\xFB",
    "-_+/AA" => "\xFB\xFF\xBF\x00",
    "-_-/" => "\xFB\xFF\xBF",
    "+_+_" => "\xFB\xFF\xBF"
  }.to_h { |string, bin| [string.b.freeze, bin.b.freeze] }.freeze

  # Rejected: bad length or padding, non-zero trailing bits, non-alphabet characters
  invalid = [
    "A", "AAAAA", "AA=", "AAA==", "AAAA=", "A===", "====", "AA=A", "AA==AA", "=AAA",
    "AB", "AB==", "AAB", "AAB=",
    "AA\nAA", "AAAA\n", "AA AA", "AA.A", "^AAA", "AAA^", "AA\0A", "AA\xFFA"
  ].map { |string| string.b.freeze }.freeze

  def ruby_encode(bin, padding: true)
    string = NATIVE_PACK.bind_call([bin], "m0").tr("+/", "-_")
    padding ? string : string.delete("=")
  end

  def ruby_decode(string)
    string = string.tr("-_", "+/")
    if !string.end_with?("=") && string.bytesize % 4 != 0
      string = string.ljust((string.bytesize + 3) & ~3, "=")
    end
    NATIVE_UNPACK1.bind_call(string, "m0")
  end

  def check_decode(mismatches, label, string)
    check(mismatches, "decode_urlsafe(#{label})", outcome { ruby_decode(string) },
      outcome { Ob64::Base64::RFC4648.decode_urlsafe(string) })
  end

  # Compares reading string through a Reader with Ruby's and decode_urlsafe
  def check_reader(mismatches, label, string)
    actual = outcome { read_all(string) { |io| Ob64::Base64::RFC4648::Reader.new(io, urlsafe: true) } }
    check(mismatches, "Reader(#{label})", outcome { ruby_decode(string) }, actual)
    check(mismatches, "Reader(#{label}) vs decode_urlsafe", outcome { Ob64::Base64::RFC4648.decode_urlsafe(string) },
      actual)
  end

  def valid_inputs(size)
    bin = rng.bytes(size)
    [true, false].flat_map do |padding|
      string = ruby_encode(bin, padding: padding)
      [string, string.tr("-_", "+/")]
    end
  end

  def broken_inputs(size)
    pool = ["=", "\n", "\r", " ", "+", "/", "-", "_", "A", "\0", "\xFF"]
    [true, false].flat_map { |padding| broken(ruby_encode(rng.bytes(size), padding: padding), pool) }
  end

  def garbage_inputs(size)
    alphabet = [*"A".."Z", *"a".."z", *"0".."9", "-", "_", "+", "/", "=", "\n"]
    [rng.bytes(size), Array.new(size) { alphabet.sample(random: rng) }.join.b]
  end

  each_codec do
    describe "fixed cases" do
      it "encodes" do
        encodings.each do |bin, (padded, unpadded)|
          expect(ruby_encode(bin)).to eq(padded), bin.inspect
          expect(ruby_encode(bin, padding: false)).to eq(unpadded), bin.inspect
          expect(Ob64::Base64::RFC4648.encode_urlsafe(bin)).to eq(padded)
          expect(Ob64::Base64::RFC4648.encode_urlsafe(bin, padding: true)).to eq(padded)
          expect(Ob64::Base64::RFC4648.encode_urlsafe(bin, padding: false)).to eq(unpadded)
          expect(Ob64::Base64::RFC4648.encode_urlsafe(bin).encoding).to eq(Encoding::US_ASCII)
          expect(Ob64::Base64::RFC4648.encode_urlsafe(bin, padding: false).encoding).to eq(Encoding::US_ASCII)
          expect(Ob64::Base64::RFC4648.encoded_length_of(bin)).to eq(padded.bytesize)
          expect(Ob64::Base64::RFC4648.encoded_length_of(bin, padding: true)).to eq(padded.bytesize)
          expect(Ob64::Base64::RFC4648.encoded_length_of(bin, padding: false)).to eq(unpadded.bytesize)
        end
      end

      it "decodes" do
        (encodings.flat_map { |bin, strings| strings.map { |string| [string, bin] } } + more_decodings.to_a)
          .each do |string, bin|
            expect(ruby_decode(string)).to eq(bin), string.inspect
            expect(Ob64::Base64::RFC4648.decode_urlsafe(string)).to eq(bin), string.inspect
            expect(Ob64::Base64::RFC4648.decode_urlsafe(string).encoding).to eq(Encoding::BINARY)
            expect(Ob64::Base64::RFC4648.decoded_length_of(string)).to eq(bin.bytesize), string.inspect
          end
      end

      it "rejects invalid input" do
        invalid.each do |string|
          expect { ruby_decode(string) }.to raise_error(ArgumentError, "invalid base64"), string.inspect
          expect { Ob64::Base64::RFC4648.decode_urlsafe(string) }
            .to raise_error(ArgumentError, "invalid base64"), string.inspect
        end
        %w[A AAAAA AAAAA==].each do |string|
          expect { Ob64::Base64::RFC4648.decoded_length_of(string) }.to raise_error(ArgumentError, "invalid base64")
        end
      end

      it "rejects bad arguments" do
        %i[encode_urlsafe decode_urlsafe encoded_length_of decoded_length_of].each do |method|
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
          [true, false].each do |padding|
            string = ruby_encode(bin, padding: padding)
            check(mismatches, "encode_urlsafe(#{size}, #{padding})", outcome { string },
              outcome { Ob64::Base64::RFC4648.encode_urlsafe(bin, padding: padding) })
            check(mismatches, "encoded_length_of(#{size}, #{padding})", string.bytesize,
              Ob64::Base64::RFC4648.encoded_length_of(bin, padding: padding))
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes valid input" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          [true, false].each do |padding|
            string = ruby_encode(bin, padding: padding)
            check_decode(mismatches, "#{size} bytes, padding: #{padding}", string)
            check_decode(mismatches, "#{size} bytes, padding: #{padding}, standard alphabet", string.tr("-_", "+/"))
            check(mismatches, "decoded_length_of(#{size}, #{padding})", size,
              Ob64::Base64::RFC4648.decoded_length_of(string))
          end
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

      # Regression: a NEON URL-safe table once accepted '^'
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
          [true, false].each do |padding|
            actual = write_all(bin) { |io| Ob64::Base64::RFC4648::Writer.new(io, urlsafe: true, padding: padding) }
            check(mismatches, "Writer(#{size}, #{padding})", ruby_encode(bin, padding: padding), actual)
            check(mismatches, "Writer(#{size}, #{padding}) vs encode_urlsafe",
              Ob64::Base64::RFC4648.encode_urlsafe(bin, padding: padding), actual)
          end
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
