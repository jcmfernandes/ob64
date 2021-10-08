# frozen_string_literal: true

RSpec.describe Ob64::Reader do
  subject(:stream) { described_class.new(io) }

  describe "#read" do
    context "when called at the end of the stream" do
      let(:io) { StringIO.new }

      it "returns an empty string when length is nil or 0" do
        expect(stream.read(nil)).to eq("")
        expect(stream.read(0)).to eq("")
      end

      it "returns nil when length is a positive integer" do
        expect(stream.read(3)).to be_nil
      end

      context "when given an outbuf" do
        it "doesn't return the outbuf" do
          outbuf = String.new
          expect(stream.read(nil, outbuf: outbuf)).not_to be outbuf
          expect(stream.read(0, outbuf: outbuf)).not_to be outbuf
        end
      end
    end

    context "when given a block" do
      let(:io) { StringIO.new("MTExMjIyMzMzNA==") }

      it "reads in chunks of at most size length" do
        iterations = 0
        stream.read(3) do |chunk|
          case iterations
          when 0
            expect(chunk).to eq("111")
          when 1
            expect(chunk).to eq("222")
          when 2
            expect(chunk).to eq("333")
          when 3
            expect(chunk).to eq("4")
          end
          iterations += 1
        end

        expect(iterations).to be 4
      end

      it "returns the number of bytes read" do
        total_bytes_read = 0
        expect(stream.read { |d| total_bytes_read += d.size }).to eq(10)
        expect(total_bytes_read).to be 10
      end

      it "uses the provided outbuf" do
        result = []
        outbuf = String.new
        stream.read(outbuf: outbuf) do |chunk|
          result << chunk
        end

        expect(result).not_to be_empty
        expect(result).to all(be(outbuf))
      end
    end

    context "when not given a block" do
      let(:io) { StringIO.new("MTExMjIyMzMzNA==") }

      it "returns a chunk of size length" do
        expect(stream.read(6)).to eq("111222")
        expect(stream.read(6)).to eq("3334")
      end

      it "uses the provided outbuf" do
        outbuf = String.new

        result = stream.read(6, outbuf: outbuf)
        expect(result).to eq("111222")
        expect(result).to be outbuf

        result = stream.read(6, outbuf: outbuf)
        expect(result).to eq("3334")
        expect(result).to be outbuf
      end
    end

    describe "errors" do
      let(:io) { StringIO.new("MTExMjIyMzMzNA==") }

      it "raises ArgumentError if length isn't a multiple of 3" do
        expect { stream.read(1) }.to raise_error(ArgumentError)
      end

      it "raises ArgumentError if length is a negative number" do
        expect { stream.read(-1) }.to raise_error(ArgumentError)
      end

      context "when attempting to decode invalid base64 data" do
        let(:io) { StringIO.new("INVALID$MzMzNA==") }

        it "raises Ob64::Decoding error" do
          expect { stream.read }.to raise_error(Ob64::DecodingError)
        end
      end
    end
  end
end
