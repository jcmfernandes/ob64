# frozen_string_literal: true

RSpec.describe "Base64 RFC 4648, loose" do
  include VariantHelpers

  # Bytes => [padded, unpadded]
  encodings = {
    "" => ["", ""],
    "\0" => ["AA==", "AA"],
    "\0\0" => ["AAA=", "AAA"],
    "\0\0\0" => ["AAAA", "AAAA"],
    "\0\0\0\0" => ["AAAAAA==", "AAAAAA"],
    "\xFF" => ["/w==", "/w"],
    "\xFF\xFF" => ["//8=", "//8"],
    "\xFF\xFF\xFF" => ["////", "////"],
    "\xFF\xFF\xFF\xFF\xFF" => ["//////8=", "//////8"],
    "\xFF\xFF\xFF\xFF\xFF\xFF" => ["////////", "////////"],
    "\xFF\xFF\xFF\xFF\xFF\xFF\xFF" => ["/////////w==", "/////////w"],
    "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xEF" => ["///////////v", "///////////v"],
    "\xFB\xFF\xBF" => ["+/+/", "+/+/"],
    "\x01\x02\x03\x04\x05" => ["AQIDBAU=", "AQIDBAU"],
    "Send reinforcements" => ["U2VuZCByZWluZm9yY2VtZW50cw==", "U2VuZCByZWluZm9yY2VtZW50cw"]
  }.to_h { |bin, strings| [bin.b.freeze, strings.map { |string| string.b.freeze }] }.freeze

  # Rejected: bad length or padding, non-zero trailing bits, non-alphabet characters
  invalid = [
    "A", "AAAAA", "AAAAAA=", "AA=", "AAA==", "AAAA=", "A===", "====", "AA=A", "AA==AA", "=AAA",
    "AB", "AB==", "AAB", "AAB=", "/x", "//9",
    "AAAA-_", "AA\nAA", "AAAA\n", "AA AA", "^", "A^", "AAA^", "AA\0", "AA\xFF", "AAAA=="
  ].map { |string| string.b.freeze }.freeze

  def ruby_encode(bin) = NATIVE_PACK.bind_call([bin], "m0")

  def ruby_decode(string)
    string = string.ljust((string.bytesize + 3) & ~3, "=") if !string.end_with?("=") && string.bytesize % 4 != 0
    NATIVE_UNPACK1.bind_call(string, "m0")
  end

  def check_decode(mismatches, label, string)
    check(mismatches, "decode(#{label})", outcome { ruby_decode(string) },
      outcome { Ob64::Base64::RFC4648.decode(string, loose: true) })
  end

  each_codec do
    describe "fixed cases" do
      it "encodes" do
        encodings.each do |bin, (padded, unpadded)|
          expect(ruby_encode(bin)).to eq(padded), bin.inspect
          expect(padded.delete("=")).to eq(unpadded)
          expect(Ob64::Base64::RFC4648.encoded_length_of(bin, padding: false)).to eq(unpadded.bytesize)
        end
      end

      it "decodes" do
        encodings.each do |bin, strings|
          strings.each do |string|
            expect(ruby_decode(string)).to eq(bin), string.inspect
            expect(Ob64::Base64::RFC4648.decode(string, loose: true)).to eq(bin), string.inspect
            expect(Ob64::Base64::RFC4648.decode(string, loose: true).encoding).to eq(Encoding::BINARY)
            expect(Ob64::Base64::RFC4648.decoded_length_of(string)).to eq(bin.bytesize), string.inspect
          end
        end
      end

      it "rejects invalid input" do
        invalid.each do |string|
          expect { ruby_decode(string) }.to raise_error(ArgumentError, "invalid base64"), string.inspect
          expect { Ob64::Base64::RFC4648.decode(string, loose: true) }
            .to raise_error(ArgumentError, "invalid base64"), string.inspect
        end
        %w[A AAAAA AAAAA==].each do |string|
          expect { Ob64::Base64::RFC4648.decoded_length_of(string) }.to raise_error(ArgumentError, "invalid base64")
        end
      end

      it "rejects bad arguments" do
        %i[decode decoded_length_of].each do |method|
          expect { Ob64::Base64::RFC4648.public_send(method, 1) }
            .to raise_error(TypeError, "no implicit conversion of Integer into String")
        end
        expect { Ob64::Base64::RFC4648.decode(1, loose: true) }
          .to raise_error(TypeError, "no implicit conversion of Integer into String")
      end
    end

    describe "random cases" do
      it "encodes" do
        mismatches = []
        sizes.each do |size|
          bin = rng.bytes(size)
          check(mismatches, "encoded_length_of(#{size}, padding: false)", ruby_encode(bin).delete("=").bytesize,
            Ob64::Base64::RFC4648.encoded_length_of(bin, padding: false))
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes valid input" do
        mismatches = []
        sizes.each do |size|
          string = ruby_encode(rng.bytes(size))
          [string, string.delete("=")].each do |input|
            check_decode(mismatches, "#{size} bytes, #{input.bytesize} chars", input)
            check(mismatches, "decoded_length_of(#{size}, #{input.bytesize})", size,
              Ob64::Base64::RFC4648.decoded_length_of(input))
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes broken input like Ruby" do
        mismatches = []
        pool = ["=", "\n", "\r", " ", "+", "/", "-", "_", "A", "\0", "\xFF"]
        sizes.each do |size|
          string = ruby_encode(rng.bytes(size)).b
          (broken(string, pool) + broken(string.delete("="), pool)).each do |input|
            check_decode(mismatches, input.inspect[0, 100], input)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes garbage like Ruby" do
        mismatches = []
        alphabet = [*"A".."Z", *"a".."z", *"0".."9", "+", "/", "=", "\n"]
        sizes.each do |size|
          [rng.bytes(size), Array.new(size) { alphabet.sample(random: rng) }.join.b].each do |string|
            check_decode(mismatches, "#{size} bytes: #{string.inspect[0, 60]}", string)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes any byte at fixed positions like Ruby" do
        mismatches = []
        valid = ruby_encode(rng.bytes(191)).b
        {"padded" => [valid, []], "unpadded" => [valid.delete("="), []], "A * 256" => [("A" * 256).b, [100]]}
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
  end
end
