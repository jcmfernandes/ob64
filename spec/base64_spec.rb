# frozen_string_literal: true

RSpec.describe Ob64::Base64 do
  example "samples" do
    expect(Ob64::Base64::RFC4648.encode("Send reinforcements")).to eq("U2VuZCByZWluZm9yY2VtZW50cw==")
    expect(Ob64::Base64::RFC4648.decode("U2VuZCByZWluZm9yY2VtZW50cw==")).to eq("Send reinforcements")
    expect(Ob64::Base64::RFC4648.encode("Now is the time for all good coders\nto learn Ruby")).to \
      eq("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ==")
    expect(Ob64::Base64::RFC4648.decode("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ==")).to \
      eq("Now is the time for all good coders\nto learn Ruby")
    expect(Ob64::Base64::RFC4648.encode("This is line one\nThis is line two\nThis is line three\nAnd so on...\n")).to \
      eq("VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K")
    expect(Ob64::Base64::RFC4648.decode("VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K")).to \
      eq("This is line one\nThis is line two\nThis is line three\nAnd so on...\n")
  end

  specify "::RFC4648.encode" do
    expect(Ob64::Base64::RFC4648.encode("")).to eq("")
    expect(Ob64::Base64::RFC4648.encode("\0")).to eq("AA==")
    expect(Ob64::Base64::RFC4648.encode("\0\0")).to eq("AAA=")
    expect(Ob64::Base64::RFC4648.encode("\0\0\0")).to eq("AAAA")
    expect(Ob64::Base64::RFC4648.encode("\0\0\0\0")).to eq("AAAAAA==")
    expect(Ob64::Base64::RFC4648.encode("\377\377\377\377\377")).to eq("//////8=")
    expect(Ob64::Base64::RFC4648.encode("\377\377\377\377\377\377")).to eq("////////")
    expect(Ob64::Base64::RFC4648.encode("\377\377\377\377\377\377\377")).to eq("/////////w==")
    expect(Ob64::Base64::RFC4648.encode("\377\377\377\377\377\377\377\xff\xef")).to eq("///////////v")
  end

  specify "::RFC4648.decode" do
    expect(Ob64::Base64::RFC4648.decode("")).to eq("")
    expect(Ob64::Base64::RFC4648.decode("AA==")).to eq("\0")
    expect(Ob64::Base64::RFC4648.decode("AAA=")).to eq("\0\0")
    expect(Ob64::Base64::RFC4648.decode("AAAA")).to eq("\0\0\0")
    expect(Ob64::Base64::RFC4648.decode("AAAAAA==")).to eq("\0\0\0\0")
    expect(Ob64::Base64::RFC4648.decode("//////8=")).to eq(in_ascii("\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode("////////")).to eq(in_ascii("\377\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode("/////////w==")).to eq(in_ascii("\377\377\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode("///////////v")).to eq(in_ascii("\377\377\377\377\377\377\377\xff\xef"))

    expect { Ob64::Base64::RFC4648.decode("AA") }.to raise_error(ArgumentError)
    expect { Ob64::Base64::RFC4648.decode("AAA") }.to raise_error(ArgumentError)
    expect { Ob64::Base64::RFC4648.decode("AAAAAA") }.to raise_error(ArgumentError)
    expect { Ob64::Base64::RFC4648.decode("//////8") }.to raise_error(ArgumentError)
    expect { Ob64::Base64::RFC4648.decode("/////////w") }.to raise_error(ArgumentError)
  end

  specify "::RFC4648.decode rejects non-zero trailing bits" do
    expect { Ob64::Base64::RFC4648.decode("AB==") }.to raise_error(ArgumentError, "invalid base64")
    expect { Ob64::Base64::RFC4648.decode("AAB=") }.to raise_error(ArgumentError, "invalid base64")
  end

  describe "::RFC4648.decode with loose: true" do
    example "accepts padded and unpadded input" do
      expect(Ob64::Base64::RFC4648.decode("", loose: true)).to eq("")
      expect(Ob64::Base64::RFC4648.decode("AA==", loose: true)).to eq("\0")
      expect(Ob64::Base64::RFC4648.decode("AA", loose: true)).to eq("\0")
      expect(Ob64::Base64::RFC4648.decode("AAA=", loose: true)).to eq("\0\0")
      expect(Ob64::Base64::RFC4648.decode("AAA", loose: true)).to eq("\0\0")
      expect(Ob64::Base64::RFC4648.decode("AAAA", loose: true)).to eq("\0\0\0")
      expect(Ob64::Base64::RFC4648.decode("AAAAAA", loose: true)).to eq("\0\0\0\0")
      expect(Ob64::Base64::RFC4648.decode("//////8", loose: true)).to eq(in_ascii("\377\377\377\377\377"))
      expect(Ob64::Base64::RFC4648.decode("/////////w", loose: true)).to eq(in_ascii("\377\377\377\377\377\377\377"))
      expect(Ob64::Base64::RFC4648.decode("/w==", loose: true)).to eq(in_ascii("\377"))
      expect(Ob64::Base64::RFC4648.decode("/w", loose: true)).to eq(in_ascii("\377"))
      expect(Ob64::Base64::RFC4648.decode("//8=", loose: true)).to eq(in_ascii("\377\377"))
      expect(Ob64::Base64::RFC4648.decode("//8", loose: true)).to eq(in_ascii("\377\377"))
      expect(Ob64::Base64::RFC4648.decode("////", loose: true)).to eq(in_ascii("\377\377\377"))
    end

    example "round-trips with the padding stripped" do
      bin = "\x01\x02\x03\x04\x05"
      expect(Ob64::Base64::RFC4648.decode(Ob64::Base64::RFC4648.encode(bin).delete("="), loose: true)).to eq(bin)
    end

    example "rejects bad padding, non-zero trailing bits and non-alphabet characters" do
      ["A", "AAAAA", "AA=", "AAA==", "AAAA=", "AA=A", "A===", "====", "AA==AA",
        "AB", "AB==", "AAB", "AAB=", "AAAA-_", "AA\nAA", "AA AA", "^", "A^", "AAA^"].each do |string|
        expect { Ob64::Base64::RFC4648.decode(string, loose: true) }.to raise_error(ArgumentError, "invalid base64"), string.inspect
      end
    end
  end

  describe "::RFC4648.encode_urlsafe" do
    example "with padding" do
      expect(Ob64::Base64::RFC4648.encode_urlsafe("")).to eq("")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0")).to eq("AA==")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0\0")).to eq("AAA=")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0\0\0")).to eq("AAAA")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0\0\0\0")).to eq("AAAAAA==")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377")).to eq("______8=")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377\377")).to eq("________")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377\377\377")).to eq("_________w==")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377\377\377\xff\xef")).to eq("___________v")
    end

    example "without padding" do
      expect(Ob64::Base64::RFC4648.encode_urlsafe("", padding: false)).to eq("")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0", padding: false)).to eq("AA")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0\0", padding: false)).to eq("AAA")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0\0\0", padding: false)).to eq("AAAA")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\0\0\0\0", padding: false)).to eq("AAAAAA")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377", padding: false)).to eq("______8")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377\377", padding: false)).to eq("________")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377\377\377", padding: false)).to eq("_________w")
      expect(Ob64::Base64::RFC4648.encode_urlsafe("\377\377\377\377\377\377\377\xff\xef", padding: false)).to eq("___________v")
    end
  end

  specify "::RFC4648.decode_urlsafe" do
    expect(Ob64::Base64::RFC4648.decode_urlsafe("")).to eq("")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("AA==")).to eq("\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("AAA=")).to eq("\0\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("AAAA")).to eq("\0\0\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("AAAAAA==")).to eq("\0\0\0\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("______8=")).to eq(in_ascii("\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("________")).to eq(in_ascii("\377\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("_________w==")).to eq(in_ascii("\377\377\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("___________v")).to eq(in_ascii("\377\377\377\377\377\377\377\xff\xef"))

    expect(Ob64::Base64::RFC4648.decode_urlsafe("AA")).to eq("\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("AAA")).to eq("\0\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("AAAAAA")).to eq("\0\0\0\0")
    expect(Ob64::Base64::RFC4648.decode_urlsafe("______8")).to eq(in_ascii("\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("_________w")).to eq(in_ascii("\377\377\377\377\377\377\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("_w==")).to eq(in_ascii("\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("_w")).to eq(in_ascii("\377"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("__8")).to eq(in_ascii("\377\377"))
  end

  specify "::RFC4648.decode_urlsafe accepts the standard alphabet" do
    expect(Ob64::Base64::RFC4648.decode_urlsafe("+/+/")).to eq(in_ascii("\xFB\xFF\xBF"))
    expect(Ob64::Base64::RFC4648.decode_urlsafe("-_+/AA")).to eq(in_ascii("\xFB\xFF\xBF\x00"))
  end

  specify "::RFC4648.decode_urlsafe rejects bad padding, non-zero trailing bits and non-alphabet characters" do
    ["A", "AAAAA", "AA=", "AAA==", "AAAA=", "AA=A", "AA==AA", "AB", "AB==", "AAB", "AAB=",
      "AA\nAA", "AA AA", "AA.A"].each do |string|
      expect { Ob64::Base64::RFC4648.decode_urlsafe(string) }.to raise_error(ArgumentError, "invalid base64"), string.inspect
    end
  end

  describe "::RFC2045.encode" do
    example "wraps lines like pack(\"m\")" do
      expect(Ob64::Base64::RFC2045.encode("")).to eq("")
      expect(Ob64::Base64::RFC2045.encode("This is data!")).to eq("VGhpcyBpcyBkYXRhIQ==\n")
      expect(Ob64::Base64::RFC2045.encode("\0" * 46)).to eq("#{"A" * 60}\nAA==\n")
      expect(Ob64::Base64::RFC2045.encode("\0" * 6, 4)).to eq("AAAA\nAAAA\n")
      expect(Ob64::Base64::RFC2045.encode("ab").encoding).to eq(Encoding::US_ASCII)
    end

    example "ends lines in CRLF with crlf: true" do
      expect(Ob64::Base64::RFC2045.encode("", crlf: true)).to eq("")
      expect(Ob64::Base64::RFC2045.encode("\0" * 46, crlf: true)).to eq("#{"A" * 60}\r\nAA==\r\n")
      expect(Ob64::Base64::RFC2045.encode("\0" * 6, 4, crlf: true)).to eq("AAAA\r\nAAAA\r\n")
      expect(Ob64::Base64::RFC2045.encoded_length_of("\0" * 46, crlf: true)).to eq 68
    end

    example "rejects line lengths that aren't positive multiples of 4" do
      [0, -4, 3, 61].each do |line_length|
        expect { Ob64::Base64::RFC2045.encode("ab", line_length) }
          .to raise_error(ArgumentError, "line length must be a positive multiple of 4: #{line_length}")
      end
      expect { Ob64::Base64::RFC2045.encode("ab", "60") }.to raise_error(TypeError)
      expect { Ob64::Base64::RFC2045.encode(1) }.to raise_error(TypeError)
    end
  end

  specify "::RFC2045.encoded_length_of" do
    expect(Ob64::Base64::RFC2045.encoded_length_of("")).to eq 0
    expect(Ob64::Base64::RFC2045.encoded_length_of("This is data!")).to eq 21
    expect(Ob64::Base64::RFC2045.encoded_length_of("\0" * 46)).to eq 66
    expect(Ob64::Base64::RFC2045.encoded_length_of("\0" * 6, 4)).to eq 10
    expect { Ob64::Base64::RFC2045.encoded_length_of("ab", 3) }
      .to raise_error(ArgumentError, "line length must be a positive multiple of 4: 3")
  end

  specify "::RFC2045.decoded_length_of" do
    expect(Ob64::Base64::RFC2045.decoded_length_of("")).to eq 0
    expect(Ob64::Base64::RFC2045.decoded_length_of("VGhpcyBp\r\ncyBkYXRhIQ==\n")).to eq 13
    expect(Ob64::Base64::RFC2045.decoded_length_of("VG hp\0cw!")).to eq 4
    expect(Ob64::Base64::RFC2045.decoded_length_of("A=AA")).to eq 2
    expect(Ob64::Base64::RFC2045.decoded_length_of("AAA=AAAA")).to eq 2
    expect { Ob64::Base64::RFC2045.decoded_length_of(1) }.to raise_error(TypeError)
  end

  specify "::RFC2045.decode skips non-alphabet characters, like unpack1(\"m\")" do
    expect(Ob64::Base64::RFC2045.decode("")).to eq("")
    expect(Ob64::Base64::RFC2045.decode("VGhpcyBp\r\ncyBkYXRhIQ==\n")).to eq("This is data!")
    expect(Ob64::Base64::RFC2045.decode("VG hp\0cw!")).to eq("This")
    expect(Ob64::Base64::RFC2045.decode("AA").encoding).to eq(Encoding::BINARY)
    expect { Ob64::Base64::RFC2045.decode(1) }.to raise_error(TypeError)
  end

  describe "::RFC4648.encoded_length_of" do
    example "with padding" do
      expect(Ob64::Base64::RFC4648.encoded_length_of("")).to eq 0
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0")).to eq 4
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0\0")).to eq 4
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0\0\0")).to eq 4
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0\0\0\0")).to eq 8
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377")).to eq 8
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377\377")).to eq 8
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377\377\377")).to eq 12
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377\377\377\xff\xef")).to eq 12
    end

    example "without padding" do
      expect(Ob64::Base64::RFC4648.encoded_length_of("", padding: false)).to eq 0
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0", padding: false)).to eq 2
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0\0", padding: false)).to eq 3
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0\0\0", padding: false)).to eq 4
      expect(Ob64::Base64::RFC4648.encoded_length_of("\0\0\0\0", padding: false)).to eq 6
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377", padding: false)).to eq 7
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377\377", padding: false)).to eq 8
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377\377\377", padding: false)).to eq 10
      expect(Ob64::Base64::RFC4648.encoded_length_of("\377\377\377\377\377\377\377\xff\xef", padding: false)).to eq 12
    end
  end

  specify "::RFC4648.decoded_length_of" do
    expect(Ob64::Base64::RFC4648.decoded_length_of("")).to eq 0
    expect(Ob64::Base64::RFC4648.decoded_length_of("AA==")).to eq 1
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAA=")).to eq 2
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA")).to eq 3
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA/w==")).to eq 4
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA//8=")).to eq 5
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA////")).to eq 6

    expect(Ob64::Base64::RFC4648.decoded_length_of("")).to eq 0
    expect(Ob64::Base64::RFC4648.decoded_length_of("AA")).to eq 1
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAA")).to eq 2
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA")).to eq 3
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA/w")).to eq 4
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA//8")).to eq 5
    expect(Ob64::Base64::RFC4648.decoded_length_of("AAAA////")).to eq 6
  end

  def in_ascii(string)
    String.new(string, encoding: "ASCII-8BIT").freeze
  end
end
