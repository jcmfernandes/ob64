# frozen_string_literal: true

require "rbconfig"

RSpec.describe "Ob64.codec_routing" do
  size_max = 2**(8 * [0].pack("J").bytesize) - 1

  def cpu_defaults
    return {neon64: 128} if RbConfig::CONFIG["host_cpu"].match?(/aarch64|arm64/)

    flags = File.foreach("/proc/cpuinfo").find { |line| line.start_with?("flags") }.to_s.split
    defaults = {}
    defaults[:avx2] = 128 if flags.include?("avx2")
    defaults[:avx512] = 1280 if flags.include?("avx512vl") && flags.include?("avx512vbmi")
    defaults
  end

  def runnable
    Ob64.codec_routing.keys
  end

  def unrunnable
    %i[avx2 avx512 neon64] - runnable
  end

  around do |example|
    saved = Ob64.codec_routing
    example.run
  ensure
    Ob64.codec_routing = saved
  end

  it "lists the codecs this CPU runs with their defaults" do
    expect(Ob64.codec_routing).to eq(cpu_defaults)
    expect(Ob64.codec_routing.keys).to eq(cpu_defaults.keys)
  end

  it "merges into the current routing" do
    skip "no SIMD codec" if runnable.empty?
    codec = runnable.first

    Ob64.codec_routing = {codec => 7}
    expect(Ob64.codec_routing).to eq(cpu_defaults.merge(codec => 7))

    Ob64.codec_routing = {}
    expect(Ob64.codec_routing).to eq(cpu_defaults.merge(codec => 7))
  end

  it "accepts nil, 0 and the largest size" do
    skip "no SIMD codec" if runnable.empty?
    codec = runnable.first

    Ob64.codec_routing = {codec => nil}
    expect(Ob64.codec_routing[codec]).to be_nil
    Ob64.codec_routing = {codec => 0}
    expect(Ob64.codec_routing[codec]).to eq(0)
    Ob64.codec_routing = {codec => size_max - 1}
    expect(Ob64.codec_routing[codec]).to eq(size_max - 1)
  end

  it "allows several codecs set to nil" do
    Ob64.codec_routing = runnable.to_h { |codec| [codec, nil] }
    expect(Ob64.codec_routing).to eq(runnable.to_h { |codec| [codec, nil] })
  end

  it "raises TypeError for a non-Hash" do
    [nil, [[:avx2, 1]], "avx2", 1].each do |arg|
      expect { Ob64.codec_routing = arg }.to raise_error(TypeError)
    end
    expect(Ob64.codec_routing).to eq(cpu_defaults)
  end

  it "raises ArgumentError for an unknown key, changing nothing" do
    [{plain: 1}, {"avx2" => 1}, {sse: 1}, {nil => 1}].each do |arg|
      expect { Ob64.codec_routing = arg }.to raise_error(ArgumentError, /unknown codec/)
    end
    expect { Ob64.codec_routing = runnable.to_h { |codec| [codec, nil] }.merge(plain: 1) }.to raise_error(ArgumentError)
    expect(Ob64.codec_routing).to eq(cpu_defaults)
  end

  it "raises ArgumentError for an invalid value, changing nothing" do
    %i[avx2 avx512 neon64].each do |codec|
      [-1, -(2**64), size_max, size_max + 1, 1.0, "1", :x, true, false].each do |value|
        expect { Ob64.codec_routing = {codec => value} }.to raise_error(ArgumentError, /invalid size/)
      end
    end
    expect { Ob64.codec_routing = runnable.to_h { |codec| [codec, 9] }.merge(avx2: -1) }.to raise_error(ArgumentError)
    expect(Ob64.codec_routing).to eq(cpu_defaults)
  end

  it "raises ArgumentError for two runnable codecs with the same value after merging, changing nothing" do
    skip "fewer than two SIMD codecs" if runnable.size < 2
    a, b = runnable

    expect { Ob64.codec_routing = {a => Ob64.codec_routing[b]} }.to raise_error(ArgumentError, "#{a} and #{b} have the same size: #{Ob64.codec_routing[b]}")
    expect { Ob64.codec_routing = {a => 5, b => 5} }.to raise_error(ArgumentError)
    expect(Ob64.codec_routing).to eq(cpu_defaults)
  end

  it "ignores known keys this CPU cannot run" do
    skip "every codec runs here" if unrunnable.empty?

    unrunnable.each do |codec|
      Ob64.codec_routing = {codec => 5}
      expect(Ob64.codec_routing).to eq(cpu_defaults)
      runnable.each do |other|
        Ob64.codec_routing = {codec => Ob64.codec_routing[other]}
        expect(Ob64.codec_routing).to eq(cpu_defaults)
      end
    end
  end

  describe "forced routing" do
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

    codecs = Ob64.codec_routing.keys
    never = codecs.to_h { |codec| [codec, nil] }
    routings = {"plain" => never}.merge(codecs.to_h { |codec| [codec.to_s, never.merge(codec => 0)] })

    routings.each do |name, routing|
      context "with #{name} only" do
        let(:rng) { Random.new(RSpec.configuration.seed) }
        let(:sizes) { (0..300).to_a + (1200..1400).to_a + [4093, 65_537, rng.rand(100_000..300_000)] }

        before { Ob64.codec_routing = routing }

        it "routes as forced" do
          expect(Ob64.codec_routing).to eq(routing)
        end

        it "encodes and decodes like native m0" do
          mismatches = []
          sizes.each do |size|
            bin = rng.bytes(size)
            encoded = NATIVE_PACK.bind_call([bin], "m0")
            urlsafe = encoded.tr("+/", "-_")

            check(mismatches, "encode(#{size})", encoded, Ob64.encode(bin))
            check(mismatches, "urlsafe_encode(#{size})", urlsafe, Ob64.urlsafe_encode(bin))
            check(mismatches, "urlsafe_encode(#{size}, padding: false)", urlsafe.delete("="),
              Ob64.urlsafe_encode(bin, padding: false))
            check(mismatches, "decode(#{size})", bin, Ob64.decode(encoded))
            check(mismatches, "decode(#{size}, loose: true)", bin, Ob64.decode(encoded, loose: true))
            check(mismatches, "decode(#{size} unpadded, loose: true)", bin, Ob64.decode(encoded.delete("="), loose: true))
            check(mismatches, "urlsafe_decode(#{size})", bin, Ob64.urlsafe_decode(urlsafe))
            check(mismatches, "urlsafe_decode(#{size} unpadded)", bin, Ob64.urlsafe_decode(urlsafe.delete("=")))
          end
          expect(mismatches).to be_empty, mismatches.first(20).join("\n")
        end

        it "decodes corrupted input like native m0" do
          mismatches = []
          sizes.each do |size|
            encoded = NATIVE_PACK.bind_call([rng.bytes(size)], "m0").b
            corruptions(rng, encoded).each do |string|
              check(mismatches, "decode(#{string.inspect[0, 100]})",
                outcome { NATIVE_UNPACK1.bind_call(string, "m0") }, outcome { Ob64.decode(string) })
              check(mismatches, "decode(#{string.inspect[0, 100]}, loose: true)",
                outcome { loose_decode(string) }, outcome { Ob64.decode(string, loose: true) })
            end
            corruptions(rng, encoded.tr("+/", "-_")).each do |string|
              check(mismatches, "urlsafe_decode(#{string.inspect[0, 100]})",
                outcome { urlsafe_decode(string) }, outcome { Ob64.urlsafe_decode(string) })
            end
          end
          expect(mismatches).to be_empty, mismatches.first(20).join("\n")
        end
      end
    end
  end
end
