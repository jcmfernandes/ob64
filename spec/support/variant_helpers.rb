# frozen_string_literal: true

require "stringio"

# Shared by the variant specs: spec/base64/*_spec.rb and spec/uu_spec.rb.
module VariantHelpers
  module ClassMethods
    # Defines a context per runnable codec, with Ob64.codec set to it.
    def each_codec(&block)
      Ob64.codecs.each do |codec|
        context "with #{codec}" do
          around do |example|
            saved = Ob64.codec
            Ob64.codec = codec
            example.run
          ensure
            Ob64.codec = saved
          end

          class_exec(codec, &block)
        end
      end
    end
  end

  # A StringIO whose readpartial and read(length) return random pieces of 1 byte to 4 KB
  class Trickle < StringIO
    def initialize(string, rng)
      super(string)
      @rng = rng
    end

    def readpartial(maxlen, outbuf = nil) = super([maxlen, piece].min, outbuf)

    def read(length = nil, outbuf = nil) = super(length && [length, piece].min, outbuf)

    private

    def piece = @rng.rand(1..(@rng.rand(2).zero? ? 4 : 4096))
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  def rng
    @rng ||= Random.new(RSpec.configuration.seed)
  end

  # Every size to 300 (SIMD blocks and tails); 1152..1536 by 4 (every AVX512 unroll remainder); around one and
  # two 4 KB batches of encoded chars: 3021 bytes (m76), 3060 (u, m), 3072 (m4, RFC 2045 decode); 4 and 8 KB;
  # large inputs
  def sizes
    [*0..300, *1152.step(1536, 4), *3019..3023, *3058..3062, *3070..3074, *4090..4100, *6118..6122, *6142..6146,
      *8188..8196, 65_537, rng.rand(100_000..300_000)]
  end

  # [:ok, value, encoding] or [:error, class, message], to compare results and errors alike. Arrays (unpack)
  # carry their elements' encodings.
  def outcome
    value = yield
    [:ok, value, value.is_a?(Array) ? value.map { |v| encoding_of(v) } : encoding_of(value)]
  rescue => e
    [:error, e.class, e.message]
  end

  def encoding_of(value) = value.respond_to?(:encoding) ? value.encoding : nil

  # Variants of string: "=", "A" or string itself appended, "=" deleted, 1-3 edits (insert, replace or delete) each a byte from
  # pool or a random one, and a truncation
  def broken(string, pool)
    string = string.b
    edited = Array.new(4) do
      s = string.dup
      rng.rand(1..3).times do
        byte = rng.rand(2).zero? ? pool.sample(random: rng).b : rng.bytes(1)
        position = rng.rand(s.bytesize + 1)
        case rng.rand(3)
        when 0 then s.insert(position, byte)
        when 1 then s[position] = byte if position < s.bytesize
        else s[position] = "" if position < s.bytesize
        end
      end
      s
    end
    [string + "=", string + "A", string + string, string.delete("="), *edited, string[0, rng.rand(string.bytesize + 1)]]
  end

  # Positions of a byte sweep in string: the first four, the middle, the last two, and extra
  def sweep_positions(string, *extra)
    size = string.bytesize
    [0, 1, 2, 3, size / 2, size - 2, size - 1, *extra].uniq
  end

  # Compares unpack1 and unpack with Ruby's, in each format
  def check_unpack(mismatches, label, string, formats)
    formats.each do |format|
      check(mismatches, "unpack1(#{label}, #{format})", outcome { NATIVE_UNPACK1.bind_call(string, format) },
        outcome { string.unpack1(format) })
      check(mismatches, "unpack(#{label}, #{format})", outcome { NATIVE_UNPACK.bind_call(string, format) },
        outcome { string.unpack(format) })
    end
  end

  def check(mismatches, label, expected, actual)
    mismatches << "#{label}: expected #{expected.inspect[0, 200]}, got #{actual.inspect[0, 200]}" if expected != actual
  end

  def expect_no_mismatches(mismatches)
    expect(mismatches).to be_empty, mismatches.first(20).join("\n")
  end

  # Writes bin, in random pieces (empty ones too) with write and <<, to the Writer the block builds on a StringIO;
  # returns the io's string
  def write_all(bin)
    io = StringIO.new
    writer = yield io
    position = 0
    loop do
      piece = bin.byteslice(position, rng.rand(0..(rng.rand(2).zero? ? 4 : 4096)))
      case rng.rand(3)
      when 0 then writer << piece
      when 1 then writer.write(piece)
      else
        cut = rng.rand(0..piece.bytesize)
        writer.write(piece.byteslice(0, cut), piece.byteslice(cut..))
      end
      position += piece.bytesize
      break if position == bin.bytesize && rng.rand(4).zero?
    end
    writer.finish.string
  end

  # Reads all with random read(length), read and readpartial calls from the Reader the block builds on a Trickle
  # of string. Raises if a read is short before the end.
  def read_all(string)
    reader = yield Trickle.new(string, rng)
    data = "".b
    loop do
      length = rng.rand(1..(rng.rand(2).zero? ? 4 : 4096))
      case rng.rand(16)
      when 0 then data << reader.read
      when 1..7
        chunk = reader.read(length)
        break unless chunk
        raise "short read(#{length}): #{chunk.bytesize}" if chunk.bytesize < length && !reader.eof?
        data << chunk
      else
        chunk = reader.readpartial(length)
        raise "readpartial(#{length}): #{chunk.bytesize}" unless chunk.bytesize.between?(1, length)
        data << chunk
      end
    end
    data
  rescue EOFError
    data
  end
end
