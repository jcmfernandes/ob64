# frozen_string_literal: true

require "spec_helper"
require "ob64/core_ext"

# Plain module methods so Ractors can call them.
module ConcurrencyCheck
  def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def self.mismatches(work, deadline)
    found = []
    loop do
      work.each do |fmt, bin, enc, dec|
        packed = [bin].pack(fmt)
        unpacked = enc.unpack1(fmt)
        all = enc.unpack(fmt)
        unless packed == enc && packed.encoding == enc.encoding && unpacked == dec &&
            unpacked.encoding == dec.encoding && all == [dec] && all[0].encoding == dec.encoding
          found << [fmt, bin.bytesize]
        end
        Thread.pass
      end
      return found if now >= deadline
    end
  end

  def self.change_routing(configs, deadline)
    i = 0
    until now >= deadline
      Ob64.codec_routing = configs[i % configs.size]
      i += 1
      Thread.pass
    end
    []
  end
end

RSpec.describe "ob64/core_ext concurrency" do
  keys = %i[avx2 avx512 neon64]
  none = keys.to_h { |k| [k, nil] }
  configs = [none, *Ob64.codec_routing.keys.flat_map { |k| [0, 64, 1280].map { |v| none.merge(k => v) } }]

  let(:rng) { Random.new(RSpec.configuration.seed) }

  # [format, binary input, native encoding, native decoding]
  def cases(count)
    Array.new(count) do
      fmt = %w[m0 m m* u u* m45 u20].sample(random: rng)
      bin = rng.bytes([0, 1, 7, 100, 127, 128, 129, 1279, 1280, 1281, 3000, rng.rand(0..4096)].sample(random: rng))
      enc = NATIVE_PACK.bind_call([bin], fmt)
      [fmt, bin.freeze, enc.freeze, NATIVE_UNPACK1.bind_call(enc, fmt).freeze]
    end
  end

  around do |example|
    saved = Ob64.codec_routing
    example.run
  ensure
    Ob64.codec_routing = none.merge(saved)
  end

  it "stays correct while another thread changes the routing" do
    work = cases(60)
    deadline = ConcurrencyCheck.now + 0.2
    changer = Thread.new { ConcurrencyCheck.change_routing(configs, deadline) }
    workers = Array.new(4) { Thread.new { ConcurrencyCheck.mismatches(work.shuffle(random: Random.new(rng.rand(1 << 30))), deadline) } }
    expect(workers.flat_map(&:value)).to eq([])
  ensure
    changer&.join
  end

  it "stays correct across Ractors while the routing changes" do
    work = cases(40).map { |c| Ractor.make_shareable(c) }
    shared = Ractor.make_shareable(configs)
    previous = Warning[:experimental]
    Warning[:experimental] = false
    deadline = ConcurrencyCheck.now + 0.2

    changer = Ractor.new(shared, deadline) { |cfgs, limit| ConcurrencyCheck.change_routing(cfgs, limit) }
    workers = Array.new(3) { Ractor.new(work, deadline) { |data, limit| ConcurrencyCheck.mismatches(data, limit) } }
    mismatches = [changer, *workers].flat_map { |r| r.respond_to?(:value) ? r.value : r.take }
    expect(mismatches).to eq([])
  ensure
    Warning[:experimental] = previous unless previous.nil?
  end
end
