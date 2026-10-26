# frozen_string_literal: true

require "spec_helper"
require "ob64/core_ext"

PACK_FORMATS = ["m", *(0..101).map { |n| "m#{n}" }, "m999999999", "m*", "u", *(0..71).map { |n| "u#{n}" }, "u999999999", "u*"].freeze
DECODE_SUBSET = %w[m m0 m3 m60 m* u u0 u5 u* m0000000000 u9].freeze
SIZES = [*0..64, *120..136, *1272..1288].freeze
NATIVES = {pack: NATIVE_PACK, unpack: NATIVE_UNPACK, unpack1: NATIVE_UNPACK1}.freeze

module CoreExtHelpers
  # Runs op on the native and the patched method with private copies of the
  # String arguments, and expects the same result, encodings, error and
  # mutated arguments. Block-form calls compare the yielded values.
  def expect_same(op, receiver, *args, block: false, **kwargs)
    outcomes = [:native, :patched].map do |impl|
      a = args.map { |v| (v.is_a?(String) && !v.frozen?) ? v.dup : v }
      kw = kwargs.transform_values { |v| (v.is_a?(String) && !v.frozen?) ? v.dup : v }
      yielded = []
      blk = block ? ->(v) { yielded << snapshot(v) } : nil
      begin
        result = if impl == :native
          NATIVES.fetch(op).bind_call(receiver, *a, **kw, &blk)
        else
          receiver.public_send(op, *a, **kw, &blk)
        end
        [:ok, snapshot(result), snapshot(a), snapshot(kw), yielded]
      rescue StandardError, ScriptError => e
        [:error, e.class, e.message, snapshot(a), snapshot(kw), yielded]
      end
    end
    expect(outcomes[1]).to eq(outcomes[0]), "#{op} #{args.inspect} #{kwargs.inspect}"
  end

  def snapshot(value)
    case value
    when String then [value, value.encoding, value.frozen?]
    when Array then value.map { |v| snapshot(v) }
    when Hash then value.transform_values { |v| snapshot(v) }
    else value
    end
  end

  def expect_same_decode(str, fmt)
    expect_same(:unpack, str, fmt)
    expect_same(:unpack1, str, fmt)
  end

  def corrupt(str, rng)
    s = str.b
    rng.rand(1..3).times do
      ch = ["=", "\n", "\r", " ", "\0", "\xFF".b, "-", "_", "!"].sample(random: rng)
      s.insert(rng.rand(0..s.bytesize), ch)
    end
    s
  end
end

RSpec.describe "ob64/core_ext" do
  include CoreExtHelpers

  let(:rng) { Random.new(RSpec.configuration.seed) }

  def random_bytes(size) = rng.bytes(size)

  def encode_sizes
    [*SIZES, *Array.new(25) { rng.rand(65..4096) }]
  end

  it "is active" do
    expect([].method(:pack).owner).not_to eq(Array)
    expect("".method(:unpack).owner).not_to eq(String)
    expect("".method(:unpack1).owner).not_to eq(String)
  end

  Ob64.codecs.each do |codec|
    describe "with #{codec}" do
      around do |example|
        saved = Ob64.codec
        Ob64.codec = codec
        example.run
      ensure
        Ob64.codec = saved
      end

      it "packs like native" do
        encode_sizes.each do |size|
          data = random_bytes(size)
          PACK_FORMATS.each { |f| expect_same(:pack, [data], f) }
        end
      end

      it "unpacks encodings like native" do
        encode_sizes.each do |size|
          data = random_bytes(size)
          PACK_FORMATS.each do |fmt|
            expect_same_decode(NATIVE_PACK.bind_call([data], fmt), fmt)
          end
        end
      end

      it "unpacks encodings with every other count like native" do
        encode_sizes.first(60).each do |size|
          data = random_bytes(size)
          PACK_FORMATS.each do |fmt|
            encoded = NATIVE_PACK.bind_call([data], fmt)
            DECODE_SUBSET.each { |f| expect_same_decode(encoded, f) }
          end
        end
      end

      it "unpacks damaged encodings like native" do
        encode_sizes.each do |size|
          data = random_bytes(size)
          DECODE_SUBSET.each do |fmt|
            encoded = NATIVE_PACK.bind_call([data], fmt.sub(/\d+|\*/, ""))
            strict = NATIVE_PACK.bind_call([data], fmt.start_with?("m") ? "m0" : "u")
            [encoded, strict].each do |enc|
              2.times { expect_same_decode(corrupt(enc, rng), fmt) }
            end
          end
        end
      end

      it "unpacks random bytes like native" do
        encode_sizes.each do |size|
          data = random_bytes(size)
          DECODE_SUBSET.each { |f| expect_same_decode(data, f) }
        end
      end

      it "unpacks random base64 alphabet text like native" do
        alphabet = [*"A".."Z", *"a".."z", *"0".."9", "+", "/", "=", "\n"]
        encode_sizes.each do |size|
          text = Array.new(size) { alphabet.sample(random: rng) }.join
          DECODE_SUBSET.each { |f| expect_same_decode(text, f) }
        end
      end

      it "handles different string encodings like native" do
        %w[UTF-8 UTF-16LE ASCII-8BIT US-ASCII].each do |enc|
          PACK_FORMATS.sample(30, random: rng).each do |fmt|
            expect_same(:pack, ["héllo wörld".encode("UTF-8").force_encoding(enc)], fmt)
            expect_same_decode("aGVsbG8=".dup.force_encoding(enc), fmt)
          end
        end
      end

      describe "fall-through" do
        let(:to_str) { Object.new.tap { |o| def o.to_str = "hello" } }

        it "matches native for mixed and odd formats" do
          formats = ["m0N", "Nm0", " m0", "m0 ", "mm", "m0m0", "M", "m0\n", "\nm0", "m-1", "m1.5", "u0u", "uN", "N", "a*", "m00",
            "m0000000000", "m1234567890", "u99999999999999999999", "m*0", "m**", "m_", "", "u ", "m\0", "m0\0", "m#", "mé"]
          formats.each do |fmt|
            expect_same(:pack, ["hello world" * 5, 1, 2], fmt)
            expect_same(:pack, ["hello world" * 5], fmt)
            expect_same_decode("aGVsbG8gd29ybGQ=\n", fmt)
          end
        end

        it "matches native for non-String formats" do
          [nil, :m0, 5, 1.5, [], to_str, Object.new, "m0".encode("UTF-16LE")].each do |fmt|
            expect_same(:pack, ["hello"], fmt)
            expect_same(:unpack, "aGVsbG8=", fmt)
            expect_same(:unpack1, "aGVsbG8=", fmt)
          end
          expect_same(:pack, ["hello"])
          expect_same(:unpack, "aGVsbG8=")
          expect_same(:unpack1, "aGVsbG8=")
        end

        it "matches native for non-String and missing elements" do
          ["m0", "m", "m5", "m*", "u", "u0", "u*"].each do |fmt|
            [[1], [nil], [:sym], [1.5], [to_str], [Object.new], [[]], [], [Class.new(String).new("sub")], [""]].each do |ary|
              expect_same(:pack, ary, fmt)
            end
          end
        end

        it "matches native for extra and frozen elements" do
          expect_same(:pack, ["a", "b"], "m0")
          expect_same(:pack, ["a"], "u")
          expect_same(:pack, ["a", "b"], "m0m0")
        end

        it "matches native with buffer:" do
          ["m0", "m", "u", "m*"].each do |fmt|
            expect_same(:pack, ["hello"], fmt, buffer: +"")
            expect_same(:pack, ["hello"], fmt, buffer: +"prefix")
            expect_same(:pack, ["hello"], fmt, buffer: "frozen")
            expect_same(:pack, ["hello"], fmt, buffer: nil)
            expect_same(:pack, ["hello"], fmt, buffer: 5)
            expect_same(:pack, ["hello"], fmt, buffer: (+"é").force_encoding("UTF-8"))
            expect_same(:pack, ["hello"], fmt, bogus: 1)
          end
        end

        it "matches native with offset:" do
          ["m0", "m", "u", "m*"].each do |fmt|
            [0, 1, 4, 8, 100, -1, nil, "1", 1.5].each do |offset|
              expect_same(:unpack, "aGVsbG8=", fmt, offset: offset)
              expect_same(:unpack1, "aGVsbG8=", fmt, offset: offset)
            end
            expect_same(:unpack, "aGVsbG8=", fmt, bogus: 1)
          end
        end

        it "matches native for block-form unpack" do
          PACK_FORMATS.sample(40, random: rng).each do |fmt|
            data = NATIVE_PACK.bind_call([random_bytes(rng.rand(0..200))], fmt)
            expect_same(:unpack, data, fmt, block: true)
            expect_same(:unpack, "garbage!!", fmt, block: true)
          end
          expect_same(:unpack, "aGVsbG8=", "m0", block: true, offset: 2)
        end

        it "matches native when line-wrapped m meets = early in a quad" do
          ["=aGk=", "a=Gk", "aG=k", "==aGk=", "=", "a=", "aGk=\n=aGk=", "aGVs\n=bG8=", "=aGVsbG8=", "a=GVsbG8="].each do |str|
            %w[m m0 m3 m60 m*].each { |fmt| expect_same_decode(str, fmt) }
            expect_same(:unpack, str, "m", block: true)
          end
        end

        it "matches native when pack and unpack1 get a block" do
          expect_same(:pack, ["hello"], "m0", block: true)
          expect_same(:pack, ["hello"], "u", block: true)
          expect_same(:unpack1, "aGVsbG8=", "m0", block: true)
          expect_same(:unpack1, "aGVsbG8=", "m", block: true)
        end

        it "matches native for empty and unusual receivers" do
          ["m0", "m", "u", "m*", "u*"].each do |fmt|
            expect_same(:unpack, "", fmt)
            expect_same(:unpack1, "", fmt)
            expect_same(:unpack, "".b.freeze, fmt)
            expect_same(:unpack, Class.new(String).new("aGk="), fmt)
          end
        end
      end
    end
  end
end
