# frozen_string_literal: true

RSpec.describe "uuencode" do
  include VariantHelpers

  # Bytes => pack("u")
  encodings = {
    "" => "",
    "\0" => "!````\n",
    "\0\0" => "\"````\n",
    "\0\0\0" => "#````\n",
    "\xFF" => "!_P``\n",
    "\xFF\xFF" => "\"__\\`\n",
    "\xFF\xFF\xFF" => "#____\n",
    "abc" => "#86)C\n",
    "This is data!" => "-5&AI<R!I<R!D871A(0``\n",
    "\0" * 45 => "M#{"`" * 60}\n",
    "\xFF" * 45 => "M#{"_" * 60}\n",
    "\0" * 46 => "M#{"`" * 60}\n!````\n",
    "\xFF" * 46 => "M#{"_" * 60}\n!_P``\n"
  }.to_h { |bin, string| [bin.b.freeze, string] }.freeze

  # [bytes, format] => pack(format): 0..2 and * mean 45 bytes a line, more than 63 means 63
  formatted = {
    ["abcdef", "u3"] => "#86)C\n#9&5F\n",
    ["abcdef", "u5"] => "#86)C\n#9&5F\n",
    ["abcdef", "u0"] => "&86)C9&5F\n",
    ["abcdef", "u*"] => "&86)C9&5F\n",
    ["\0" * 46, "u*"] => "M#{"`" * 60}\n!````\n",
    ["\0" * 64, "u64"] => "_#{"`" * 84}\n!````\n",
    ["\0" * 64, "u999999999"] => "_#{"`" * 84}\n!````\n"
  }.to_h { |(bin, format), string| [[bin.b.freeze, format], string] }.freeze

  # Malformed input => unpack1("u"): decoding stops at the first line not starting with "!".."`", never raises
  quirks = {
    "\n" => "",
    "#86)C" => "abc",
    "#86)C\r\n#86)C\r\n" => "abcabc",
    "#86)C\r#9&5F\r" => "abcdef",
    "$86)C\n" => "abc\0",
    "!86)C\n" => "a",
    "#86" => "a`",
    "#86)CX\n#9&5F\n" => "abcdef",
    "a86)C\n" => "",
    "#86)C\na\n" => "abc",
    "#86)C\n~86)C\n" => "abc",
    "#86)C\n\x7F86)C\n" => "abc",
    "#86)C\n\xFF86)C\n" => "abc",
    "#86)~\n" => "ab@",
    "!    \n" => "\0",
    " \n#86)C\n" => "",
    "#86)C\n \n#86)C\n" => "abc",
    "`\n#86)C\n" => "abc"
  }.to_h { |string, bin| [string.b.freeze, bin.b] }.freeze

  pack_formats = ["u", "u*", *(0..71).map { |n| "u#{n}" }, "u999999999"].freeze
  # Unpack ignores the count
  unpack_formats = %w[u u* u0 u5 u9].freeze

  def ruby_encode(bin, format = "u") = NATIVE_PACK.bind_call([bin], format)

  def ruby_decode(string, format = "u") = NATIVE_UNPACK1.bind_call(string, format)

  # Compares every decoding path with Ruby's
  def check_decode(mismatches, label, string, formats)
    expected = outcome { ruby_decode(string) }
    check(mismatches, "decode(#{label})", expected, outcome { Ob64::UU.decode(string) })
    check(mismatches, "decoded_length_of(#{label})", expected[1].bytesize, Ob64::UU.decoded_length_of(string)) if expected[0] == :ok
    check_unpack(mismatches, label, string, formats)
  end

  # Line quirks and a "~" at 4 KB batch edges
  def line_variants(string, pool)
    lines = string.lines
    sprinkled = string.dup
    rng.rand(1..20).times { sprinkled.insert(rng.rand(sprinkled.bytesize + 1), pool.sample(random: rng).b) }
    [
      string.gsub("\n", "\r\n"),
      string + ruby_encode(rng.bytes(rng.rand(1..44))).b + string,
      sprinkled,
      lines.map { |line| rng.rand(4).zero? ? line.sub(/\n\z/) { "#{rng.rand(0x20..0x60).chr}\n" } : line }.join,
      lines.map(&:dup).tap { |l| l[rng.rand(l.size)][0] = rng.rand(0x20..0x7F).chr unless l.empty? }.join.b,
      string.dup.tap { |s| s[rng.rand(s.bytesize)] = ["a", "~", "\x7F", "\xFF", "\n"].sample(random: rng).b unless s.empty? },
      *[63, 64, 65, 4095, 4096, 4097].select { |offset| offset < string.bytesize }.map { |offset| string.dup.tap { |s| s[offset] = "~" } }
    ]
  end

  each_codec do
    describe "fixed cases" do
      it "encodes" do
        encodings.each do |bin, string|
          expect(ruby_encode(bin)).to eq(string), bin.inspect
          expect(Ob64::UU.encode(bin)).to eq(string)
          expect(Ob64::UU.encode(bin).encoding).to eq(Encoding::US_ASCII)
          expect(Ob64::UU.encoded_length_of(bin)).to eq(string.bytesize)
          expect([bin].pack("u")).to eq(string)
          expect([bin].pack("u").encoding).to eq(Encoding::US_ASCII)
        end
        formatted.each do |(bin, format), string|
          expect(ruby_encode(bin, format)).to eq(string), format
          expect([bin].pack(format)).to eq(string)
          expect([bin].pack(format).encoding).to eq(Encoding::US_ASCII)
        end
      end

      it "decodes" do
        (encodings.map { |bin, string| [string, bin] } + formatted.map { |(bin, _), string| [string, bin] }).each do |string, bin|
          expect(ruby_decode(string)).to eq(bin), string.inspect
          expect(Ob64::UU.decode(string)).to eq(bin)
          expect(Ob64::UU.decode(string).encoding).to eq(Encoding::BINARY)
          expect(Ob64::UU.decoded_length_of(string)).to eq(bin.bytesize)
          unpack_formats.each do |format|
            expect(string.unpack1(format)).to eq(bin)
            expect(string.unpack(format)).to eq([bin])
          end
        end
      end

      it "decodes malformed input like Ruby" do
        quirks.each do |string, bin|
          expect(ruby_decode(string)).to eq(bin), string.inspect
          expect(Ob64::UU.decode(string)).to eq(bin), string.inspect
          expect(Ob64::UU.decode(string).encoding).to eq(Encoding::BINARY)
          expect(Ob64::UU.decoded_length_of(string)).to eq(bin.bytesize), string.inspect
          unpack_formats.each do |format|
            expect(string.unpack1(format)).to eq(bin), string.inspect
            expect(string.unpack(format)).to eq([bin]), string.inspect
          end
        end
      end

      it "rejects bad arguments" do
        %i[encode decode encoded_length_of decoded_length_of].each do |method|
          expect { Ob64::UU.public_send(method, 1) }
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
          check(mismatches, "encode(#{size})", outcome { string }, outcome { Ob64::UU.encode(bin) })
          check(mismatches, "encoded_length_of(#{size})", string.bytesize, Ob64::UU.encoded_length_of(bin))
          pack_formats.each do |format|
            check(mismatches, "pack(#{size}, #{format})", outcome { ruby_encode(bin, format) }, outcome { [bin].pack(format) })
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes valid input" do
        mismatches = []
        sizes.each_with_index do |size, i|
          bin = rng.bytes(size)
          format = (i % 7).zero? ? "u" : "u#{3 + i % 61}"
          string = ruby_encode(bin, format)
          check_decode(mismatches, "#{size} bytes in #{format}", string, [*unpack_formats, "m0000000000"])
          check(mismatches, "decoded_length_of(#{size}, #{format})", size, Ob64::UU.decoded_length_of(string))
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes broken input like Ruby" do
        mismatches = []
        pool = ["\n", "\r\n", "\r", " ", "\t", "`", "!", "~", "a", "=", "-", "_", "\0", "\x7F", "\x80", "\xFF"]
        sizes.each_with_index do |size, i|
          format = (i % 7).zero? ? "u" : "u#{3 + i % 61}"
          string = ruby_encode(rng.bytes(size), format).b
          (broken(string, pool) + line_variants(string, pool)).each do |s|
            check_decode(mismatches, s.inspect[0, 100], s, unpack_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes garbage like Ruby" do
        mismatches = []
        uu_alphabet = [*" ".."`", "\n"]
        base64_alphabet = [*"A".."Z", *"a".."z", *"0".."9", "+", "/", "=", "\n"]
        sizes.each do |size|
          [
            rng.bytes(size),
            Array.new(size) { uu_alphabet.sample(random: rng) }.join.b,
            Array.new(size) { base64_alphabet.sample(random: rng) }.join.b,
            NATIVE_PACK.bind_call([rng.bytes(size)], "m")
          ].each do |string|
            check_decode(mismatches, "#{size} bytes: #{string.inspect[0, 60]}", string, unpack_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end

      it "decodes any byte at fixed positions like Ruby" do
        mismatches = []
        valid = ruby_encode(rng.bytes(45 * 20)).b
        sweep_positions(valid, 4, 63, 300).each do |position|
          (0..255).each do |byte|
            string = valid.dup
            string.setbyte(position, byte)
            check_decode(mismatches, "byte #{byte} at #{position}", string, unpack_formats)
          end
        end
        expect_no_mismatches(mismatches)
      end
    end
  end
end
