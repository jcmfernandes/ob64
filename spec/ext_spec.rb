# frozen_string_literal: true

RSpec.describe Ob64::Ext do
  include VariantHelpers

  let(:ext) { Object.new.extend(Ob64::Ext) }

  def call(name, *args) = ext.send(name, *args)

  # dst prefixes: empty, embedded and heap-sized, binary and not
  def prefixes = ["".b, "ab".b, "é", "x".b * 1000, "y" * 1000]

  # [name, one-shot] per _into helper: the one-shot decodes a String; the _into one appends to dst from src[0, len]
  # and returns what the one-shot's result maps to
  intos = {
    "__decode_into" => [
      ->(ext, string) { ext.send(:__decode, string, false, true) },
      ->(ext, dst, src, len) { ext.send(:__decode_into, dst, src, len, false, true) }
    ],
    "__decode_rfc_2045_into" => [
      ->(ext, string) { ext.send(:__decode_rfc_2045, string) },
      ->(ext, dst, src, len) { ext.send(:__decode_rfc_2045_into, dst, src, len) }
    ],
    "__uudecode_capped_into" => [
      ->(ext, string) { ext.send(:__uudecode_capped, string, 50_000) },
      ->(ext, dst, src, len) { ext.send(:__uudecode_capped_into, dst, src, len, 50_000) }
    ]
  }

  intos.each do |name, (_, into)|
    describe name do
      let(:src) { (name == "__uudecode_capped_into") ? "#86)C\n#86)C\n" : "YWJjYWJj" }

      it "keeps dst's encoding" do
        dst = +"é"
        into.call(ext, dst, src, src.bytesize)
        expect(dst.encoding).to eq(Encoding::UTF_8)
        expect(dst.b).to eq("éabcabc".b)
      end

      it "raises FrozenError on a frozen dst" do
        expect { into.call(ext, "ab".b.freeze, src, 4) }.to raise_error(FrozenError)
      end

      it "raises ArgumentError when dst is src" do
        dst = src.dup
        expect { into.call(ext, dst, dst, 4) }.to raise_error(ArgumentError, "dst and src must differ")
      end

      it "raises ArgumentError on a length out of src, leaving dst unchanged" do
        [-1, src.bytesize + 1, 2**62].each do |len|
          dst = +"ab"
          expect { into.call(ext, dst, src, len) }.to raise_error(ArgumentError)
          expect(dst).to eq("ab")
        end
      end
    end
  end

  it "returns dst from __decode_into" do
    dst = +"ab"
    expect(call(:__decode_into, dst, "YWJj", 4, false, false)).to be(dst)
    expect(dst).to eq("ababc")
  end

  it "leaves dst unchanged on invalid input to __decode_into" do
    prefixes.each do |prefix|
      dst = prefix.dup
      expect { call(:__decode_into, dst, "YWJj!", 5, false, false) }.to raise_error(ArgumentError, "invalid base64")
      expect(dst).to eq(prefix)
      expect(dst.encoding).to eq(prefix.encoding)
    end
  end

  it "returns the bytes appended from __decode_rfc_2045_into" do
    dst = +"ab"
    expect(call(:__decode_rfc_2045_into, dst, "YW\nJj", 5)).to eq(3)
    expect(dst).to eq("ababc")
  end

  it "returns stopped from __uudecode_capped_into" do
    dst = +"ab"
    expect(call(:__uudecode_capped_into, dst, "#86)C\n\n#86)C\n", 13, 2**62)).to be(true)
    expect(dst).to eq("ababc")
    expect(call(:__uudecode_capped_into, dst, "#86)C\n#86)C\n", 12, 2)).to be(false)
    expect(dst).to eq("ababcab")
  end

  it "raises ArgumentError on a negative cap to __uudecode_capped_into" do
    expect { call(:__uudecode_capped_into, +"", "#86)C\n", 6, -1) }.to raise_error(ArgumentError)
  end

  each_codec do
    # Random bytes encoded, then broken; a random prefix of each decoded into each dst prefix
    {
      "__decode_into" => [Ob64::Base64::RFC4648.method(:encode), %w[= A + /]],
      "__decode_rfc_2045_into" => [Ob64::Base64::RFC2045.method(:encode), %w[= A + / \n]],
      "__uudecode_capped_into" => [Ob64::UU.method(:encode), %w[` ! M a \n]]
    }.each do |name, (encode, pool)|
      it "#{name} appends what the one-shot decodes, or leaves dst unchanged" do
        one_shot = intos[name][0]
        into = intos[name][1]
        mismatches = []
        [0, 1, 2, 3, 4, 5, 63, 64, 65, 300, 3060, 4100, 70_000].each do |size|
          encoded = encode.call(rng.bytes(size))
          [encoded, *broken(encoded, pool)].each do |src|
            len = rng.rand(0..src.bytesize)
            label = "#{name}(#{src.inspect[0, 40]}, #{len})"
            expected = outcome { one_shot.call(ext, src.byteslice(0, len)) }
            expected[1] = Array(expected[1])[0] if expected[0] == :ok
            prefixes.each do |prefix|
              dst = prefix.dup
              actual = outcome do
                into.call(ext, dst, src, len)
                dst.byteslice(prefix.bytesize..).b
              end
              check(mismatches, label, expected[0..1], actual[0..1])
              check(mismatches, "#{label} prefix", [prefix, prefix.encoding], [dst.byteslice(0, prefix.bytesize), dst.encoding])
            end
          end
        end
        expect_no_mismatches(mismatches)
      end
    end
  end

  # [one-shot, argument sets] per appending helper: it appends to dst what the one-shot (nil: none) makes of
  # src[off, len]
  appends = {
    "__encode_into" => [:__encode, [[false, true], [true, false], [false, false], [true, true]]],
    "__encode_rfc_2045_into" => [:__encode_rfc_2045, [[76, false], [4, true], [8, false], [64, true]]],
    "__uuencode_into" => [:__uuencode, [[]]],
    "__append_into" => [nil, [[]]]
  }

  appends.each do |name, (_, arg_sets)|
    describe name do
      let(:src) { "\x00abc\xFFdefgh".b }
      let(:args) { arg_sets[0] }

      define_method(:into) { |dst, src, off, len| call(name, dst, src, off, len, *args) }

      it "returns dst, keeping its encoding" do
        dst = +"é"
        expect(into(dst, src, 1, 3)).to be(dst)
        expect(dst.encoding).to eq(Encoding::UTF_8)
        expect(dst.byteslice(0, 2)).to eq("é")
      end

      it "raises FrozenError on a frozen dst" do
        expect { into("ab".b.freeze, src, 0, 1) }.to raise_error(FrozenError)
      end

      it "raises ArgumentError when dst is src" do
        dst = src.dup
        expect { into(dst, dst, 0, 1) }.to raise_error(ArgumentError, "dst and src must differ")
      end

      it "raises ArgumentError on off and len out of src, leaving dst unchanged" do
        [[-1, 0], [src.bytesize + 1, 0], [0, -1], [0, src.bytesize + 1], [1, src.bytesize], [2, 2**62]].each do |off, len|
          dst = +"ab"
          expect { into(dst, src, off, len) }.to raise_error(ArgumentError)
          expect(dst).to eq("ab")
        end
      end
    end
  end

  it "raises ArgumentError on an invalid line length to __encode_rfc_2045_into, leaving dst unchanged" do
    [0, 3, 6, -4].each do |line_length|
      dst = +"ab"
      expect { call(:__encode_rfc_2045_into, dst, "abc", 0, 3, line_length, false) }
        .to raise_error(ArgumentError, "line length must be a positive multiple of 4: #{line_length}")
      expect(dst).to eq("ab")
    end
  end

  it "clears dst's code range in __append_into" do
    dst = +"aé"
    expect(dst.valid_encoding?).to be(true)
    call(:__append_into, dst, "\xFF".b, 0, 1)
    expect(dst.valid_encoding?).to be(false)
  end

  each_codec do
    # Random bytes, a random range of each appended to each dst prefix
    appends.each do |name, (one_shot, arg_sets)|
      it "#{name} appends what the one-shot makes" do
        mismatches = []
        [0, 1, 2, 3, 4, 5, 44, 45, 46, 63, 64, 65, 300, 3060, 4100, 70_000].each do |size|
          src = rng.bytes(size)
          arg_sets.each do |args|
            off = rng.rand(0..size)
            [[0, size], [off, rng.rand(0..(size - off))]].each do |o, len|
              label = "#{name}(#{size} bytes, #{o}, #{len}, #{args.inspect})"
              piece = src.byteslice(o, len)
              expected = one_shot ? call(one_shot, piece, *args) : piece
              prefixes.each do |prefix|
                dst = prefix.dup
                call(name, dst, src, o, len, *args)
                check(mismatches, label, expected.b, dst.byteslice(prefix.bytesize..).b)
                check(mismatches, "#{label} prefix", [prefix, prefix.encoding], [dst.byteslice(0, prefix.bytesize), dst.encoding])
              end
            end
          end
        end
        expect_no_mismatches(mismatches)
      end
    end
  end

  describe "__consume" do
    it "drops the first n bytes in place and returns str" do
      prefixes.each do |prefix|
        str = prefix + "abc"
        [0, 1, str.bytesize].each do |n|
          s = str.dup
          expect(call(:__consume, s, n)).to be(s)
          expect(s).to eq(str.byteslice(n..))
          expect(s.encoding).to eq(str.encoding)
        end
      end
    end

    it "raises on a frozen str or n out of str" do
      expect { call(:__consume, "ab".b.freeze, 1) }.to raise_error(FrozenError)
      [-1, 3].each do |n|
        str = +"ab"
        expect { call(:__consume, str, n) }.to raise_error(ArgumentError)
        expect(str).to eq("ab")
      end
    end
  end

  describe "__copy_into" do
    let(:src) { "0123456789".b * 200 }

    it "replaces dst's content with src[off, n], keeping its encoding, and returns dst" do
      prefixes.each do |prefix|
        [[0, 0], [3, 2], [0, src.bytesize], [5, 1500], [src.bytesize, 0]].each do |off, n|
          dst = prefix.dup
          expect(call(:__copy_into, dst, src, off, n)).to be(dst)
          expect(dst.b).to eq(src.byteslice(off, n))
          expect(dst.encoding).to eq(prefix.encoding)
        end
      end
    end

    it "raises on a frozen dst, dst being src, or off and n out of src" do
      expect { call(:__copy_into, "ab".b.freeze, src, 0, 1) }.to raise_error(FrozenError)
      expect { call(:__copy_into, src, src, 0, 1) }.to raise_error(ArgumentError, "dst and src must differ")
      [[-1, 0], [src.bytesize + 1, 0], [0, -1], [1, src.bytesize], [2, 2**62]].each do |off, n|
        dst = +"ab"
        expect { call(:__copy_into, dst, src, off, n) }.to raise_error(ArgumentError)
        expect(dst).to eq("ab")
      end
    end
  end
end
