# frozen_string_literal: true

RSpec.describe Ob64::UU do
  let(:rng) { Random.new(RSpec.configuration.seed) }
  let(:inputs) { (0..200).map { |size| rng.bytes(size) } + [rng.bytes(4096)] }

  specify ".encode matches pack(\"u\")" do
    inputs.each do |bin|
      encoded = Ob64::UU.encode(bin)
      expect(encoded).to eq(NATIVE_PACK.bind_call([bin], "u"))
      expect(encoded.encoding).to eq(Encoding::US_ASCII)
    end
    expect { Ob64::UU.encode(1) }.to raise_error(TypeError, "no implicit conversion of Integer into String")
  end

  specify ".decode matches unpack1(\"u\")" do
    encodings = inputs.map { |bin| NATIVE_PACK.bind_call([bin], "u") }
    damaged = encodings.map do |enc|
      enc.dup.insert(rng.rand(enc.size + 1), ["\n", "\r", " ", "a", "~", "\0"].sample(random: rng))
    end
    garbage = Array.new(100) { rng.bytes(rng.rand(200)) }

    (encodings + damaged + garbage).each do |string|
      decoded = Ob64::UU.decode(string)
      expect(decoded).to eq(NATIVE_UNPACK1.bind_call(string, "u"))
      expect(decoded.encoding).to eq(Encoding::BINARY)
    end
    expect { Ob64::UU.decode(1) }.to raise_error(TypeError, "no implicit conversion of Integer into String")
  end
end
