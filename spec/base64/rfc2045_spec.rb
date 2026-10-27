# frozen_string_literal: true

RSpec.describe "Base64 RFC 2045" do
  include VariantHelpers

  # Bytes => encoding, default line length
  encodings = {
    "" => "",
    "\0" => "AA==\n",
    "\0\0" => "AAA=\n",
    "\0\0\0" => "AAAA\n",
    "\0\0\0\0" => "AAAAAA==\n",
    "\xFF" => "/w==\n",
    "\xFF\xFF" => "//8=\n",
    "\xFF\xFF\xFF" => "////\n",
    "\xFB\xFF\xBF" => "+/+/\n",
    "\0" * 45 => "#{"A" * 60}\n",
    "\0" * 46 => "#{"A" * 60}\nAA==\n",
    "\xFF" * 45 => "#{"/" * 60}\n",
    "This is data!" => "VGhpcyBpcyBkYXRhIQ==\n",
    "Send reinforcements" => "U2VuZCByZWluZm9yY2VtZW50cw==\n",
    "Now is the time for all good coders\nto learn Ruby" =>
      "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g\nUnVieQ==\n",
    "This is line one\nThis is line two\nThis is line three\nAnd so on...\n" =>
      "VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGlu\nZSB0aHJlZQpBbmQgc28gb24uLi4K\n"
  }.to_h { |bin, string| [bin.b.freeze, string] }.freeze

  # [bytes, line length (nil: default), crlf] => encoding
  wrapped = {
    ["", nil, true] => "",
    ["\0" * 45, 60, true] => "#{"A" * 60}\r\n",
    ["\0" * 46, nil, true] => "#{"A" * 60}\r\nAA==\r\n",
    ["\0", 4, false] => "AA==\n",
    ["\0" * 4, 4, true] => "AAAA\r\nAA==\r\n",
    ["\0" * 6, 4, false] => "AAAA\nAAAA\n",
    ["\0" * 6, 4, true] => "AAAA\r\nAAAA\r\n",
    ["\xFF" * 7, 8, false] => "////////\n/w==\n",
    ["\0" * 57, 76, false] => "#{"A" * 76}\n",
    ["\0" * 58, 76, true] => "#{"A" * 76}\r\nAA==\r\n",
    ["\0" * 100, 2_863_311_528, false] => "#{"A" * 132}AA==\n",
    ["\0" * 100, 2_863_311_528, true] => "#{"A" * 132}AA==\r\n"
  }.to_h { |(bin, line_length, crlf), string| [[bin.b.freeze, line_length, crlf].freeze, string] }.freeze

  # Lenient decoding: non-alphabet characters skipped, "=" in 3rd or 4th place of a group stops decoding, never raises
  quirks = {
    "VGhpcyBp\r\ncyBkYXRhIQ==\n" => "This is data!",
    "VG hp\0cw!" => "This",
    "\tAA AA\n" => "\0\0\0",
    "AA-_AA" => "\0\0\0",
    "\xFFAA\x80AA" => "\0\0\0",
    "AAAA" => "\0\0\0",
    "A" => "",
    "AA" => "\0",
    "AAA" => "\0\0",
    "AAAAA" => "\0\0\0",
    "AB==" => "\0",
    "AAB=" => "\0\0",
    "/x==" => "\xFF",
    "====" => "",
    "=AAA" => "\0\0",
    "A=AA" => "\0\0",
    "AA=A" => "\0",
    "AAA=AAAA" => "\0\0",
    "AA==AA" => "\0",
    "AAAA=AAAA" => "\0" * 6,
    "AAAA==\nAAAA" => "\0" * 6,
    # = early in a quad
    "=aGk=" => "hi",
    "a=Gk" => "hi",
    "aG=k" => "h",
    "==aGk=" => "hi",
    "=" => "",
    "a=" => "",
    "aGk=\n=aGk=" => "hi",
    "aGVs\n=bG8=" => "hello",
    "=aGVsbG8=" => "hello",
    "a=GVsbG8=" => "hello"
  }.to_h { |string, bin| [string.b.freeze, bin.b.freeze] }.freeze

  # Encodings and decodings through pack and unpack
  formats = ["m", "m*", *(0..101).map { |n| "m#{n}" }, "m3072", "m5000", "m999999999"].freeze
  decode_formats = %w[m m* m3 m60].freeze
  line_lengths = [nil, 4, 60, 76, 400, 4096, 6668].freeze

  junk = ["\n", "\r\n", "\r", " ", "\t", "\0", "\x80", "\xFF", "-", "_", "!", "~", "a", "=", "+", "/", "A"]
    .map { |byte| byte.b.freeze }.freeze

  def ruby_encode(bin, line_length = nil, crlf: false)
    string = NATIVE_PACK.bind_call([bin], line_length ? "m#{line_length / 4 * 3}" : "m")
    crlf ? string.gsub("\n", "\r\n") : string
  end

  def ruby_decode(string) = NATIVE_UNPACK1.bind_call(string, "m")

  # Compares every decoding path with Ruby's
  def check_decode(mismatches, label, string, formats)
    expected = outcome { ruby_decode(string) }
    check(mismatches, "decode(#{label})", expected, outcome { Ob64::Base64::RFC2045.decode(string) })
    if expected[0] == :ok
      check(mismatches, "decoded_length_of(#{label})", expected[1].bytesize,
        Ob64::Base64::RFC2045.decoded_length_of(string))
    end
    check_unpack(mismatches, label, string, formats)
  end

  # Expects every decoding path to turn each string into its bytes
  def expect_decodes(table, formats)
    table.each do |string, bin|
      expect(ruby_decode(string)).to eq(bin), string.inspect
      expect(Ob64::Base64::RFC2045.decode(string)).to eq(bin), string.inspect
      expect(Ob64::Base64::RFC2045.decode(string).encoding).to eq(Encoding::BINARY)
      expect(Ob64::Base64::RFC2045.decoded_length_of(string)).to eq(bin.bytesize), string.inspect
      formats.each do |fmt|
        expect(string.unpack1(fmt)).to eq(bin), string.inspect
        expect(string.unpack1(fmt).encoding).to eq(Encoding::BINARY)
        expect(string.unpack(fmt)).to eq([bin]), string.inspect
      end
      yielded = []
      string.unpack("m") { |value| yielded << value }
      expect(yielded).to eq([bin])
    end
  end

  def sprinkle(string, count, pool)
    s = string.b
    count.times { s.insert(rng.rand(0..s.bytesize), pool.sample(random: rng)) }
    s
  end

  # CRLF, newlines removed, junk sprinkled, truncated, "=" inserted, junk at SIMD block and 4 KB batch edges
  def m_variants(encoded, pool)
    [
      encoded,
      encoded.gsub("\n", "\r\n"),
      encoded.delete("\n"),
      sprinkle(encoded, rng.rand(1..50), pool),
      encoded[0, rng.rand(0..encoded.bytesize)],
      encoded.dup.insert(rng.rand(0..encoded.bytesize), "="),
      *[63, 64, 65, 4095, 4096, 4097].select { |offset| offset <= encoded.bytesize }
        .map { |offset| encoded.dup.insert(offset, pool.sample(random: rng)) }
    ]
  end

  # "=" after 0..3 chars of a group, past a long clean prefix
  def equals_variants(size, pool)
    (0..3).flat_map do |position|
      prefix = NATIVE_PACK.bind_call([rng.bytes(size / 3 * 3)], "m0").b
      suffix = "QUJD"[0, position] + "=" + NATIVE_PACK.bind_call([rng.bytes(100)], "m").b
      [prefix + suffix, sprinkle(prefix, rng.rand(1..20), pool) + suffix]
    end
  end

  each_codec do
    describe "fixed cases" do
      it "encodes" do
        encodings.each do |bin, string|
          expect(ruby_encode(bin)).to eq(string), bin.inspect
          expect(Ob64::Base64::RFC2045.encode(bin)).to eq(string)
          expect(Ob64::Base64::RFC2045.encode(bin).encoding).to eq(Encoding::US_ASCII)
          expect(Ob64::Base64::RFC2045.encoded_length_of(bin)).to eq(string.bytesize)
          %w[m m45].each do |fmt|
            expect([bin].pack(fmt)).to eq(string)
            expect([bin].pack(fmt).encoding).to eq(Encoding::US_ASCII)
          end
        end
        wrapped.each do |(bin, line_length, crlf), string|
          args = [bin, *line_length]
          expect(ruby_encode(*args, crlf: crlf)).to eq(string), [bin, line_length, crlf].inspect
          expect(Ob64::Base64::RFC2045.encode(*args, crlf: crlf)).to eq(string)
          expect(Ob64::Base64::RFC2045.encode(*args, crlf: crlf).encoding).to eq(Encoding::US_ASCII)
          expect(Ob64::Base64::RFC2045.encoded_length_of(*args, crlf: crlf)).to eq(string.bytesize)
          expect([bin].pack("m#{(line_length || 60) / 4 * 3}")).to eq(string) unless crlf
        end
      end

      it "decodes" do
        expect_decodes({**encodings.invert, **wrapped.to_h { |(bin, _, _), string| [string, bin] }}, decode_formats)
      end

      it "decodes malformed input like Ruby" do
        expect_decodes(quirks, decode_formats)
      end

      it "rejects bad arguments" do
        %i[encode decode encoded_length_of decoded_length_of].each do |method|
          expect { Ob64::Base64::RFC2045.public_send(method, 1) }
            .to raise_error(TypeError, "no implicit conversion of Integer into String")
        end
        [0, -4, 3, 61, 2_863_311_532].each do |line_length|
          %i[encode encoded_length_of].each do |method|
            expect { Ob64::Base64::RFC2045.public_send(method, "ab", line_length) }
              .to raise_error(ArgumentError, "line length must be a positive multiple of 4: #{line_length}")
          end
        end
        %i[encode encoded_length_of].each do |method|
          expect { Ob64::Base64::RFC2045.public_send(method, "ab", "60") }
            .to raise_error(TypeError, "no implicit conversion of String into Integer")
          expect { Ob64::Base64::RFC2045.public_send(method, "ab", 2**64) }.to raise_error(RangeError)
        end
      end
    end

    describe "random cases" do
      it "encodes" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          line_lengths.product([false, true]).each do |line_length, crlf|
            args = [bin, *line_length]
            label = "#{size}, #{line_length.inspect}, crlf: #{crlf}"
            string = ruby_encode(*args, crlf: crlf)
            check(mismatches, "encode(#{label})", outcome { string },
              outcome { Ob64::Base64::RFC2045.encode(*args, crlf: crlf) })
            check(mismatches, "encoded_length_of(#{label})", string.bytesize,
              Ob64::Base64::RFC2045.encoded_length_of(*args, crlf: crlf))
          end
          formats.each do |fmt|
            check(mismatches, "pack(#{size}, #{fmt})", outcome { NATIVE_PACK.bind_call([bin], fmt) },
              outcome { [bin].pack(fmt) })
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes valid input" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          formats.each do |fmt|
            string = NATIVE_PACK.bind_call([bin], fmt)
            check_decode(mismatches, "#{size} bytes in #{fmt}", string, [fmt, "m", "m0000000000"].uniq)
          end
          line_lengths.each do |line_length|
            string = ruby_encode(bin, *line_length, crlf: true)
            check_decode(mismatches, "#{size} bytes, #{line_length.inspect}, crlf: true", string, decode_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes broken input like Ruby" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          [ruby_encode(bin), NATIVE_PACK.bind_call([bin], %w[m0 m3 m60 m76 m300 m999].sample(random: rng))].each do |encoded|
            encoded = encoded.b
            (broken(encoded, junk) + m_variants(encoded, junk)).each do |string|
              check_decode(mismatches, string.inspect[0, 100], string, decode_formats)
            end
          end
          equals_variants(size, junk).each do |string|
            check_decode(mismatches, string.inspect[0, 100], string, decode_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes garbage like Ruby" do
        mismatches = []
        alphabet = [*"A".."Z", *"a".."z", *"0".."9", "+", "/", "=", "\n"]
        uu_alphabet = [*" ".."`", "\n"]
        sizes.each do |size|
          [
            rng.bytes(size),
            Array.new(size) { alphabet.sample(random: rng) }.join.b,
            Array.new(size) { uu_alphabet.sample(random: rng) }.join.b,
            NATIVE_PACK.bind_call([rng.bytes(size)], "u")
          ].each do |string|
            check_decode(mismatches, "#{size} bytes: #{string.inspect[0, 60]}", string, decode_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes any byte at fixed positions like Ruby" do
        mismatches = []
        valid = ruby_encode(rng.bytes(3000)).b
        sweep_positions(valid, 100, 1000).each do |position|
          (0..255).each do |byte|
            string = valid.dup
            string.setbyte(position, byte)
            check_decode(mismatches, "byte #{byte} at #{position}", string, decode_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end
    end
  end
end
