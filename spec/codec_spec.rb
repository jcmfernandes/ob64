# frozen_string_literal: true

require "rbconfig"

RSpec.describe "Ob64.codec" do
  # OB64_CODECS: the codecs CI expects, e.g. "scalar,avx2,avx512"; also right
  # under an emulator, where /proc/cpuinfo shows the host CPU.
  def cpu_codecs
    return ENV["OB64_CODECS"].split(",").map(&:to_sym) if ENV["OB64_CODECS"]
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
end
