# frozen_string_literal: true

require "rbconfig"

RSpec.describe "Ob64.codec" do
  def cpu_codecs
    return %i[scalar neon64] if RbConfig::CONFIG["host_cpu"].match?(/aarch64|arm64/)

    flags = File.foreach("/proc/cpuinfo").find { |line| line.start_with?("flags") }.to_s.split
    codecs = [:scalar]
    codecs << :avx2 if flags.include?("avx2")
    codecs << :avx512 if flags.include?("avx512vl") && flags.include?("avx512vbmi") && flags.include?("avx512_vbmi2")
    codecs
  end

  around do |example|
    saved = Ob64.codec
    example.run
  ensure
    Ob64.codec = saved
  end

  it "lists the codecs this CPU runs, best last" do
    expect(Ob64.codecs).to eq(cpu_codecs)
  end

  it "defaults to the best codec" do
    expect(Ob64.best_codec).to eq(cpu_codecs.last)
    expect(Ob64.codec).to eq(Ob64.best_codec)
  end

  it "keeps the best codec when another is forced" do
    Ob64.codec = :scalar
    expect(Ob64.best_codec).to eq(cpu_codecs.last)
  end

  it "sets each runnable codec" do
    Ob64.codecs.each do |codec|
      expect(Ob64.public_send(:codec=, codec)).to eq(codec)
      expect(Ob64.codec).to eq(codec)
    end
  end

  it "raises ArgumentError for an unknown codec, keeping the current one" do
    current = Ob64.codec = Ob64.codecs.last
    [:sse, "scalar", nil, 1].each do |arg|
      expect { Ob64.codec = arg }.to raise_error(ArgumentError, "unknown codec: #{arg.inspect}")
      expect(Ob64.codec).to eq(current)
    end
  end

  it "raises ArgumentError for a codec this CPU cannot run, keeping the current one" do
    unrunnable = %i[avx2 avx512 neon64] - Ob64.codecs
    skip "every codec runs here" if unrunnable.empty?

    current = Ob64.codec = Ob64.codecs.last
    unrunnable.each do |codec|
      expect { Ob64.codec = codec }.to raise_error(ArgumentError, "#{codec} is not supported by this CPU")
      expect(Ob64.codec).to eq(current)
    end
  end

  describe "forced codec" do
    def outcome
      [:ok, yield]
    rescue => e
      [:error, e.class, e.message]
    end

    def loose_decode(string)
      if !string.end_with?("=") && string.bytesize % 4 != 0
        string = string.ljust((string.bytesize + 3) & ~3, "=")
      end
      NATIVE_UNPACK1.bind_call(string, "m0")
    end

    def urlsafe_decode(string)
      loose_decode(string.tr("-_", "+/"))
    end

    def corruptions(rng, string)
      pool = ["=", "\n", " ", "+", "/", "-", "_", "A", "\0", "\xFF".b]
      [string + "=", string + "A", string.delete("=")] +
        Array.new(4) do
          corrupted = string.dup
          position = rng.rand(corrupted.bytesize + 1)
          byte = rng.rand(2).zero? ? pool.sample(random: rng) : rng.bytes(1)
          if position == corrupted.bytesize || rng.rand(3).zero?
            corrupted.insert(position, byte)
          elsif rng.rand(2).zero?
            corrupted[position] = byte
          else
            corrupted[position] = ""
          end
          corrupted
        end
    end

    def check(mismatches, label, expected, actual)
      mismatches << "#{label}: expected #{expected.inspect[0, 200]}, got #{actual.inspect[0, 200]}" if expected != actual
    end

    Ob64.codecs.each do |codec|
      context "with #{codec}" do
        let(:rng) { Random.new(RSpec.configuration.seed) }
        let(:sizes) { (0..300).to_a + (1200..1400).to_a + [4093, 65_537, rng.rand(100_000..300_000)] }

        before { Ob64.codec = codec }

        it "is current" do
          expect(Ob64.codec).to eq(codec)
        end

        it "encodes and decodes like native m0" do
          mismatches = []
          sizes.each do |size|
            bin = rng.bytes(size)
            encoded = NATIVE_PACK.bind_call([bin], "m0")
            urlsafe = encoded.tr("+/", "-_")

            check(mismatches, "encode(#{size})", encoded, Ob64::Base64.encode(bin))
            check(mismatches, "urlsafe_encode(#{size})", urlsafe, Ob64::Base64.urlsafe_encode(bin))
            check(mismatches, "urlsafe_encode(#{size}, padding: false)", urlsafe.delete("="),
              Ob64::Base64.urlsafe_encode(bin, padding: false))
            check(mismatches, "decode(#{size})", bin, Ob64::Base64.decode(encoded))
            check(mismatches, "decode(#{size}, loose: true)", bin, Ob64::Base64.decode(encoded, loose: true))
            check(mismatches, "decode(#{size} unpadded, loose: true)", bin, Ob64::Base64.decode(encoded.delete("="), loose: true))
            check(mismatches, "urlsafe_decode(#{size})", bin, Ob64::Base64.urlsafe_decode(urlsafe))
            check(mismatches, "urlsafe_decode(#{size} unpadded)", bin, Ob64::Base64.urlsafe_decode(urlsafe.delete("=")))
          end
          expect(mismatches).to be_empty, mismatches.first(20).join("\n")
        end

        it "decodes corrupted input like native m0" do
          mismatches = []
          sizes.each do |size|
            encoded = NATIVE_PACK.bind_call([rng.bytes(size)], "m0").b
            corruptions(rng, encoded).each do |string|
              check(mismatches, "decode(#{string.inspect[0, 100]})",
                outcome { NATIVE_UNPACK1.bind_call(string, "m0") }, outcome { Ob64::Base64.decode(string) })
              check(mismatches, "decode(#{string.inspect[0, 100]}, loose: true)",
                outcome { loose_decode(string) }, outcome { Ob64::Base64.decode(string, loose: true) })
            end
            corruptions(rng, encoded.tr("+/", "-_")).each do |string|
              check(mismatches, "urlsafe_decode(#{string.inspect[0, 100]})",
                outcome { urlsafe_decode(string) }, outcome { Ob64::Base64.urlsafe_decode(string) })
            end
          end
          expect(mismatches).to be_empty, mismatches.first(20).join("\n")
        end

        it "decodes any byte in a SIMD block like native m0" do
          mismatches = []
          (0..255).each do |byte|
            [0, 1, 2, 3, 100].each do |position|
              string = ("A" * 256).b
              string.setbyte(position, byte)
              check(mismatches, "decode(#{byte} at #{position})",
                outcome { NATIVE_UNPACK1.bind_call(string, "m0") }, outcome { Ob64::Base64.decode(string) })
              check(mismatches, "urlsafe_decode(#{byte} at #{position})",
                outcome { urlsafe_decode(string) }, outcome { Ob64::Base64.urlsafe_decode(string) })
            end
          end
          expect(mismatches).to be_empty, mismatches.first(20).join("\n")
        end
      end
    end
  end
end
