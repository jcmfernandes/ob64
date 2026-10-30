# frozen_string_literal: true

RSpec.describe "Streams" do
  bin = (0..255).map(&:chr).join.b * 3 + "\0"
  big = Random.new(42).bytes(4 << 20)

  # Returns the objects allocated by the block
  def allocated
    GC.start
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end

  # Writer => its module's encode
  {
    Ob64::Base64::RFC4648::Writer => Ob64::Base64::RFC4648.method(:encode),
    Ob64::Base64::RFC2045::Writer => Ob64::Base64::RFC2045.method(:encode),
    Ob64::UU::Writer => Ob64::UU.method(:encode)
  }.each do |klass, encode|
    describe klass do
      let(:io) { StringIO.new }
      let(:writer) { klass.new(io) }

      it "returns the bytes taken from write and self from <<" do
        expect(writer.write).to eq(0)
        expect(writer.write("ab", "", "é")).to eq(4)
        expect(writer.write("x", 1)).to eq(2)
        expect(writer << "c").to be(writer)
        expect(writer.finish.string).to eq(encode.call("abéx1c".b))
      end

      it "converts every argument before taking any" do
        expect(writer.write("abc", 1)).to eq(4)
        expect { writer.write("def", BasicObject.new) }.to raise_error(TypeError)
        expect(writer.finish.string).to eq(encode.call("abc1"))
      end

      it "writes what the io failed to take with the next write" do
        writes = 0
        io.define_singleton_method(:write) do |string|
          raise IOError, "full" if (writes += 1) == 1
          super(string)
        end
        expect { writer << bin }.to raise_error(IOError, "full")
        writer << bin
        expect(writer.finish.string).to eq(encode.call(bin * 2))
      end

      it "flushes the io, keeping a partial group" do
        expect(io).to receive(:flush)
        writer << bin
        expect(writer.flush).to be(writer)
        expect(io.string).not_to be_empty
        expect(encode.call(bin)).to start_with(io.string)
        expect(io.string.bytesize).to be < encode.call(bin).bytesize
      end

      it "keeps the io open and returns it from finish" do
        writer << bin
        expect(writer.finish).to be(io)
        expect(io).not_to be_closed
        expect(io.string).to eq(encode.call(bin))
      end

      it "closes the io and returns nil from close" do
        writer << bin
        expect(writer.close).to be_nil
        expect(io).to be_closed
        expect(io.string).to eq(encode.call(bin))
      end

      it "closes the io after finish, and closing twice does nothing" do
        writer << bin
        writer.finish
        expect(writer.close).to be_nil
        expect(io).to be_closed
        expect(io.string).to eq(encode.call(bin))
        expect(writer.close).to be_nil
      end

      it "raises IOError after finish or close" do
        %i[finish close].each do |method|
          writer = klass.new(StringIO.new)
          writer.public_send(method)
          expect { writer.write("a") }.to raise_error(IOError, "closed stream")
          expect { writer << "a" }.to raise_error(IOError, "closed stream")
          expect { writer.flush }.to raise_error(IOError, "closed stream")
          expect { writer.finish }.to raise_error(IOError, "closed stream")
        end
      end

      it "gives the io the same String on every write, which it must not keep" do
        written = +""
        strings = []
        sink = Object.new
        sink.define_singleton_method(:write) do |string|
          strings << string
          written << string
          string.bytesize
        end
        writer = klass.new(sink)
        writer << bin
        writer.write(bin, "a", bin)
        writer << bin
        writer.finish
        expect(strings.size).to be > 1
        expect(strings).to all(be(strings.first))
        expect(written).to eq(encode.call(bin * 2 + "a" + bin * 2))
      end

      context "with 1000 writes of 1000 bytes" do
        chunk = Random.new(7).bytes(1000).freeze

        # A binary StringIO, as one with another encoding converts what it is
        # written, allocating
        let(:io) { StringIO.new(+"".b) }

        it "allocates nothing per <<" do
          writer << chunk
          count = allocated { 1000.times { writer << chunk } }
          expect(count).to be < 20
          expect(writer.finish.string).to eq(encode.call(chunk * 1001))
        end

        it "allocates only the arguments Array per write" do
          writer.write(chunk)
          count = allocated { 1000.times { writer.write(chunk) } }
          expect(count).to be < 1020
          expect(writer.finish.string).to eq(encode.call(chunk * 1001))
        end
      end
    end
  end

  # Reader => its module's encode
  {
    Ob64::Base64::RFC4648::Reader => Ob64::Base64::RFC4648.method(:encode),
    Ob64::Base64::RFC2045::Reader => Ob64::Base64::RFC2045.method(:encode),
    Ob64::UU::Reader => Ob64::UU.method(:encode)
  }.each do |klass, encode|
    describe klass do
      let(:io) { StringIO.new(encode.call(bin)) }
      let(:reader) { klass.new(io) }

      it "reads like IO#read" do
        expect(reader.read(0)).to eq("")
        expect(reader.read(5)).to eq(bin[0, 5])
        expect(reader.read(5).encoding).to eq(Encoding::BINARY)
        expect(reader.read).to eq(bin[10..])
        expect(reader.read.encoding).to eq(Encoding::BINARY)
        expect(reader.read(0)).to eq("")
        expect(reader.read(1)).to be_nil
      end

      it "reads fewer bytes than asked only at the end" do
        expect(reader.read(bin.bytesize - 1)).to eq(bin[0...-1])
        expect(reader.read(5)).to eq(bin[-1])
      end

      it "replaces and returns outbuf" do
        outbuf = +"old"
        expect(reader.read(2, outbuf)).to be(outbuf)
        expect(outbuf).to eq(bin[0, 2])
        expect(reader.readpartial(2, outbuf)).to be(outbuf)
        expect(outbuf).to eq(bin[2, 2])
        expect(reader.read(nil, outbuf)).to be(outbuf)
        expect(outbuf).to eq(bin[4..])
        expect(reader.read(nil, outbuf)).to be(outbuf)
        expect(outbuf).to eq("")
        outbuf = +"old"
        expect(reader.read(1, outbuf)).to be_nil
        expect(outbuf).to eq("")
      end

      it "reads like IO#readpartial" do
        expect(reader.readpartial(0)).to eq("")
        expect(reader.readpartial(5)).to eq(bin[0, 5])
        expect(reader.readpartial(5).encoding).to eq(Encoding::BINARY)
        expect(reader.readpartial(bin.bytesize)).to eq(bin[10..])
        expect(reader.readpartial(0)).to eq("")
        expect { reader.readpartial(1) }.to raise_error(EOFError)
      end

      it "clears outbuf at the end of readpartial" do
        reader.read
        outbuf = +"old"
        expect { reader.readpartial(1, outbuf) }.to raise_error(EOFError)
        expect(outbuf).to eq("")
      end

      it "returns what is decoded without waiting for more text" do
        blocked = Object.new
        chunks = [encode.call("abcdef".b)]
        blocked.define_singleton_method(:readpartial) do |_maxlen, outbuf|
          chunks.empty? ? raise("blocked") : outbuf.replace(chunks.shift)
        end
        expect(klass.new(blocked).readpartial(1_000_000)).to eq("abcdef")
      end

      it "reads an io returning frozen Strings of its own" do
        frozen = Object.new
        text = encode.call(bin).freeze
        frozen.define_singleton_method(:readpartial) do |_maxlen, _outbuf|
          text.empty? ? raise(EOFError) : text.tap { text = "" }
        end
        expect(klass.new(frozen).read).to eq(bin)
      end

      it "tells eof" do
        expect(reader.eof?).to be(false)
        reader.read(bin.bytesize)
        expect(reader.eof?).to be(true)
        expect(reader.eof).to be(true)
      end

      it "rejects a negative length" do
        expect { reader.read(-1) }.to raise_error(ArgumentError, "negative length -1 given")
        expect { reader.readpartial(-1) }.to raise_error(ArgumentError, "negative length -1 given")
      end

      it "closes the io and returns nil from close" do
        expect(reader.close).to be_nil
        expect(io).to be_closed
      end

      context "with 4 MB of text" do
        let(:io) { StringIO.new(encode.call(big)) }
        # Allocations allowed per 64 KiB pulled, and in all
        let(:slack) { io.size / 65_536 * 2 + 20 }

        it "allocates nothing per read with outbuf" do
          reader = klass.new(io)
          outbuf = +""
          total = 0
          count = allocated { total += outbuf.bytesize while reader.read(1000, outbuf) }
          expect(total).to eq(big.bytesize)
          expect(count).to be < slack
        end

        it "allocates a String per read without outbuf" do
          reader = klass.new(io)
          reads = 0
          count = allocated { reads += 1 while reader.read(1000) }
          expect(reads).to eq((big.bytesize + 999) / 1000)
          expect(count).to be_between(reads, reads + slack)
        end
      end
    end
  end
end
