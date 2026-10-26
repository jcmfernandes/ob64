# frozen_string_literal: true

require "spec_helper"
require "ob64/core_ext"

RSpec.describe "line-wrapped m and u" do
  junk = ["\n", "\r\n", " ", "\t", "\0", "\x80".b, "\xFF".b, "-", "_", "!", "~", "a"].freeze

  around do |example|
    saved = Ob64.codec
    example.run
  ensure
    Ob64.codec = saved
  end

  def check(mismatches, label, expected, actual)
    mismatches << "#{label}: expected #{expected.inspect[0, 200]}, got #{actual.inspect[0, 200]}" if expected != actual
  end

  def expect_none(mismatches)
    expect(mismatches).to be_empty, mismatches.first(20).join("\n")
  end

  def sprinkle(string, rng, count, pool)
    s = string.b
    count.times { s.insert(rng.rand(0..s.bytesize), pool.sample(random: rng)) }
    s
  end

  def boundaries = [63, 64, 65, 4095, 4096, 4097]

  def at_offsets(encoded, offsets)
    offsets.select { |offset| offset <= encoded.bytesize }.map { |offset| yield(encoded.dup, offset) }
  end

  def m_variants(encoded, rng, pool)
    [
      encoded,
      encoded.gsub("\n", "\r\n"),
      encoded.delete("\n"),
      sprinkle(encoded, rng, rng.rand(1..50), pool),
      encoded[0, rng.rand(0..encoded.bytesize)],
      encoded.dup.insert(rng.rand(0..encoded.bytesize), "="),
      rng.bytes(rng.rand(0..200)),
      *at_offsets(encoded, boundaries) { |s, offset| s.insert(offset, pool.sample(random: rng)) }
    ]
  end

  # "=" after 0..3 chars of a group, past a long clean prefix
  def equals_variants(size, rng, pool)
    (0..3).flat_map do |pos|
      prefix = NATIVE_PACK.bind_call([rng.bytes(size / 3 * 3)], "m0").b
      suffix = "QUJD"[0, pos] + "=" + NATIVE_PACK.bind_call([rng.bytes(100)], "m").b
      [prefix + suffix, sprinkle(prefix, rng, rng.rand(1..20), pool) + suffix]
    end
  end

  def u_variants(encoded, rng, pool)
    lines = encoded.lines
    [
      encoded,
      encoded.gsub("\n", "\r\n"),
      encoded + NATIVE_PACK.bind_call([rng.bytes(rng.rand(1..44))], "u").b + encoded,
      sprinkle(encoded, rng, rng.rand(1..20), pool),
      encoded[0, rng.rand(0..encoded.bytesize)],
      lines.map { |line| rng.rand(4).zero? ? line.sub(/\n\z/) { "#{rng.rand(0x20..0x60).chr}\n" } : line }.join,
      with_bad_length(lines, rng),
      with_out_of_range(encoded, rng),
      rng.bytes(rng.rand(0..200)),
      *at_offsets(encoded, boundaries.reject { |offset| offset == encoded.bytesize }) { |s, offset| s.tap { s[offset] = "~" } }
    ]
  end

  def with_bad_length(lines, rng)
    return "".b if lines.empty?
    lines = lines.map(&:dup)
    lines[rng.rand(lines.size)][0] = rng.rand(0x20..0x7F).chr
    lines.join
  end

  def with_out_of_range(encoded, rng)
    return encoded if encoded.empty?
    s = encoded.dup
    s[rng.rand(s.bytesize)] = ["a", "~", "\x7F".b, "\xFF".b, "\n"].sample(random: rng)
    s
  end

  Ob64.codecs.each do |codec|
    context "with #{codec}" do
      let(:rng) { Random.new(RSpec.configuration.seed) }
      let(:sizes) { [*0..200, *1000..1100, 4093, 65_537, rng.rand(100_000..300_000)] }

      before { Ob64.codec = codec }

      it "packs m like native" do
        mismatches = []
        formats = ["m", "m*", "m0", *[1, 2, 3, 4, 5, 6, 30, 45, 57, 60, 72, 75, 76, 300, 999, 3072, 5000].map { |n| "m#{n}" }]
        sizes.each do |size|
          bin = rng.bytes(size)
          formats.each do |fmt|
            expected = NATIVE_PACK.bind_call([bin], fmt)
            actual = [bin].pack(fmt)
            check(mismatches, "pack(#{fmt}, #{size})", [expected, expected.encoding], [actual, actual.encoding])
          end
        end
        expect_none(mismatches)
      end

      it "unpacks m like native" do
        mismatches = []
        sizes.each do |size|
          fmt = ["m", "m3", "m60", "m76", "m300", "m999"].sample(random: rng)
          encoded = NATIVE_PACK.bind_call([rng.bytes(size)], fmt).b
          (m_variants(encoded, rng, junk) + equals_variants(size, rng, junk)).each do |string|
            %w[m m*].each do |f|
              expected = NATIVE_UNPACK1.bind_call(string, f)
              actual = string.unpack1(f)
              check(mismatches, "unpack1(#{string.inspect[0, 100]}, #{f})", [expected, expected.encoding], [actual, actual.encoding])
            end
          end
        end
        expect_none(mismatches)
      end

      it "unpacks m with any byte at fixed positions like native" do
        mismatches = []
        encoded = NATIVE_PACK.bind_call([rng.bytes(3000)], "m").b
        (0..255).each do |byte|
          [0, 1, 2, 3, 100, 1000].each do |position|
            string = encoded.dup
            string.setbyte(position, byte)
            expected = NATIVE_UNPACK1.bind_call(string, "m")
            actual = string.unpack1("m")
            check(mismatches, "unpack1(#{byte} at #{position})", [expected, expected.encoding], [actual, actual.encoding])
          end
        end
        expect_none(mismatches)
      end

      it "packs u like native" do
        mismatches = []
        formats = ["u", "u*", *(0..64).map { |n| "u#{n}" }, "u999"]
        [*0..100, 4093, 65_537].each do |size|
          bin = rng.bytes(size)
          formats.each do |fmt|
            expected = NATIVE_PACK.bind_call([bin], fmt)
            actual = [bin].pack(fmt)
            check(mismatches, "pack(#{fmt}, #{size})", [expected, expected.encoding], [actual, actual.encoding])
          end
          expected = NATIVE_PACK.bind_call([bin], "u")
          check(mismatches, "UU.encode(#{size})", expected, Ob64::UU.encode(bin))
          check(mismatches, "UU.encoded_length_of(#{size})", expected.bytesize, Ob64::UU.encoded_length_of(bin))
        end
        expect_none(mismatches)
      end

      it "unpacks u like native" do
        mismatches = []
        sizes.each_with_index do |size, i|
          fmt = (i % 7).zero? ? "u" : "u#{3 + i % 61}"
          encoded = NATIVE_PACK.bind_call([rng.bytes(size)], fmt).b
          u_variants(encoded, rng, junk).each do |string|
            expected = NATIVE_UNPACK1.bind_call(string, "u")
            actual = string.unpack1("u")
            label = string.inspect[0, 100]
            check(mismatches, "unpack1(#{label})", [expected, expected.encoding], [actual, actual.encoding])
            check(mismatches, "UU.decode(#{label})", expected, Ob64::UU.decode(string))
            check(mismatches, "UU.decoded_length_of(#{label})", expected.bytesize, Ob64::UU.decoded_length_of(string))
          end
        end
        expect_none(mismatches)
      end

      it "unpacks u with any byte at fixed positions like native" do
        mismatches = []
        encoded = NATIVE_PACK.bind_call([rng.bytes(45 * 20)], "u").b
        (0..255).each do |byte|
          [1, 2, 3, 4, 63, 300].each do |position|
            string = encoded.dup
            string.setbyte(position, byte)
            expected = NATIVE_UNPACK1.bind_call(string, "u")
            actual = string.unpack1("u")
            label = "#{byte} at #{position}"
            check(mismatches, "unpack1(#{label})", [expected, expected.encoding], [actual, actual.encoding])
            check(mismatches, "UU.decode(#{label})", expected, Ob64::UU.decode(string))
            check(mismatches, "UU.decoded_length_of(#{label})", expected.bytesize, Ob64::UU.decoded_length_of(string))
          end
        end
        expect_none(mismatches)
      end
    end
  end
end
