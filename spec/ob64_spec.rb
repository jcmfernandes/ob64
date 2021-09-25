# frozen_string_literal: true

RSpec.describe Ob64 do
  example "samples" do
    expect(Ob64.encode("Send reinforcements")).to eq("U2VuZCByZWluZm9yY2VtZW50cw==")
    expect(Ob64.decode("U2VuZCByZWluZm9yY2VtZW50cw==")).to eq("Send reinforcements")
    expect(Ob64.encode("Now is the time for all good coders\nto learn Ruby")).to \
      eq("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ==")
    expect(Ob64.decode("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ==")).to \
      eq("Now is the time for all good coders\nto learn Ruby")
    expect(Ob64.encode("This is line one\nThis is line two\nThis is line three\nAnd so on...\n")).to \
      eq("VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K")
    expect(Ob64.decode("VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGluZSB0aHJlZQpBbmQgc28gb24uLi4K")).to \
      eq("This is line one\nThis is line two\nThis is line three\nAnd so on...\n")
  end

  specify ".encode" do
    expect(Ob64.encode("")).to eq("")
    expect(Ob64.encode("\0")).to eq("AA==")
    expect(Ob64.encode("\0\0")).to eq("AAA=")
    expect(Ob64.encode("\0\0\0")).to eq("AAAA")
    expect(Ob64.encode("\0\0\0\0")).to eq("AAAAAA==")
    expect(Ob64.encode("\377\377\377\377\377")).to eq("//////8=")
    expect(Ob64.encode("\377\377\377\377\377\377")).to eq("////////")
    expect(Ob64.encode("\377\377\377\377\377\377\377")).to eq("/////////w==")
    expect(Ob64.encode("\377\377\377\377\377\377\377\xff\xef")).to eq("///////////v")
  end

  specify ".decode" do
    expect(Ob64.decode("")).to eq("")
    expect(Ob64.decode("AA==")).to eq("\0")
    expect(Ob64.decode("AAA=")).to eq("\0\0")
    expect(Ob64.decode("AAAA")).to eq("\0\0\0")
    expect(Ob64.decode("AAAAAA==")).to eq("\0\0\0\0")
    expect(Ob64.decode("//////8=")).to eq(in_ascii("\377\377\377\377\377"))
    expect(Ob64.decode("////////")).to eq(in_ascii("\377\377\377\377\377\377"))
    expect(Ob64.decode("/////////w==")).to eq(in_ascii("\377\377\377\377\377\377\377"))
    expect(Ob64.decode("///////////v")).to eq(in_ascii("\377\377\377\377\377\377\377\xff\xef"))

    expect { Ob64.decode("AA") }.to raise_error(ArgumentError)
    expect { Ob64.decode("AAA") }.to raise_error(ArgumentError)
    expect { Ob64.decode("AAAAAA") }.to raise_error(ArgumentError)
    expect { Ob64.decode("//////8") }.to raise_error(ArgumentError)
    expect { Ob64.decode("/////////w") }.to raise_error(ArgumentError)
  end

  describe ".urlsafe_encode" do
    example "with padding" do
      expect(Ob64.urlsafe_encode("")).to eq("")
      expect(Ob64.urlsafe_encode("\0")).to eq("AA==")
      expect(Ob64.urlsafe_encode("\0\0")).to eq("AAA=")
      expect(Ob64.urlsafe_encode("\0\0\0")).to eq("AAAA")
      expect(Ob64.urlsafe_encode("\0\0\0\0")).to eq("AAAAAA==")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377")).to eq("______8=")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377\377")).to eq("________")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377\377\377")).to eq("_________w==")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377\377\377\xff\xef")).to eq("___________v")
    end

    example "without padding" do
      expect(Ob64.urlsafe_encode("", padding: false)).to eq("")
      expect(Ob64.urlsafe_encode("\0", padding: false)).to eq("AA")
      expect(Ob64.urlsafe_encode("\0\0", padding: false)).to eq("AAA")
      expect(Ob64.urlsafe_encode("\0\0\0", padding: false)).to eq("AAAA")
      expect(Ob64.urlsafe_encode("\0\0\0\0", padding: false)).to eq("AAAAAA")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377", padding: false)).to eq("______8")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377\377", padding: false)).to eq("________")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377\377\377", padding: false)).to eq("_________w")
      expect(Ob64.urlsafe_encode("\377\377\377\377\377\377\377\xff\xef", padding: false)).to eq("___________v")
    end
  end

  specify ".urlsafe_decode" do
    expect(Ob64.urlsafe_decode("")).to eq("")
    expect(Ob64.urlsafe_decode("AA==")).to eq("\0")
    expect(Ob64.urlsafe_decode("AAA=")).to eq("\0\0")
    expect(Ob64.urlsafe_decode("AAAA")).to eq("\0\0\0")
    expect(Ob64.urlsafe_decode("AAAAAA==")).to eq("\0\0\0\0")
    expect(Ob64.urlsafe_decode("______8=")).to eq(in_ascii("\377\377\377\377\377"))
    expect(Ob64.urlsafe_decode("________")).to eq(in_ascii("\377\377\377\377\377\377"))
    expect(Ob64.urlsafe_decode("_________w==")).to eq(in_ascii("\377\377\377\377\377\377\377"))
    expect(Ob64.urlsafe_decode("___________v")).to eq(in_ascii("\377\377\377\377\377\377\377\xff\xef"))

    expect(Ob64.urlsafe_decode("AA")).to eq("\0")
    expect(Ob64.urlsafe_decode("AAA")).to eq("\0\0")
    expect(Ob64.urlsafe_decode("AAAAAA")).to eq("\0\0\0\0")
    expect(Ob64.urlsafe_decode("______8")).to eq(in_ascii("\377\377\377\377\377"))
    expect(Ob64.urlsafe_decode("_________w")).to eq(in_ascii("\377\377\377\377\377\377\377"))
  end

  describe ".encoded_length_of" do
    example "with padding" do
      expect(Ob64.encoded_length_of("")).to eq 0
      expect(Ob64.encoded_length_of("\0")).to eq 4
      expect(Ob64.encoded_length_of("\0\0")).to eq 4
      expect(Ob64.encoded_length_of("\0\0\0")).to eq 4
      expect(Ob64.encoded_length_of("\0\0\0\0")).to eq 8
      expect(Ob64.encoded_length_of("\377\377\377\377\377")).to eq 8
      expect(Ob64.encoded_length_of("\377\377\377\377\377\377")).to eq 8
      expect(Ob64.encoded_length_of("\377\377\377\377\377\377\377")).to eq 12
      expect(Ob64.encoded_length_of("\377\377\377\377\377\377\377\xff\xef")).to eq 12
    end

    example "without padding" do
      expect(Ob64.encoded_length_of("", padding: false)).to eq 0
      expect(Ob64.encoded_length_of("\0", padding: false)).to eq 2
      expect(Ob64.encoded_length_of("\0\0", padding: false)).to eq 3
      expect(Ob64.encoded_length_of("\0\0\0", padding: false)).to eq 4
      expect(Ob64.encoded_length_of("\0\0\0\0", padding: false)).to eq 6
      expect(Ob64.encoded_length_of("\377\377\377\377\377", padding: false)).to eq 7
      expect(Ob64.encoded_length_of("\377\377\377\377\377\377", padding: false)).to eq 8
      expect(Ob64.encoded_length_of("\377\377\377\377\377\377\377", padding: false)).to eq 10
      expect(Ob64.encoded_length_of("\377\377\377\377\377\377\377\xff\xef", padding: false)).to eq 12
    end
  end

  specify ".decoded_length_of" do
    expect(Ob64.decoded_length_of("")).to eq 0
    expect(Ob64.decoded_length_of("AA==")).to eq 1
    expect(Ob64.decoded_length_of("AAA=")).to eq 2
    expect(Ob64.decoded_length_of("AAAA")).to eq 3
    expect(Ob64.decoded_length_of("AAAA/w==")).to eq 4
    expect(Ob64.decoded_length_of("AAAA//8=")).to eq 5
    expect(Ob64.decoded_length_of("AAAA////")).to eq 6

    expect(Ob64.decoded_length_of("")).to eq 0
    expect(Ob64.decoded_length_of("AA")).to eq 1
    expect(Ob64.decoded_length_of("AAA")).to eq 2
    expect(Ob64.decoded_length_of("AAAA")).to eq 3
    expect(Ob64.decoded_length_of("AAAA/w")).to eq 4
    expect(Ob64.decoded_length_of("AAAA//8")).to eq 5
    expect(Ob64.decoded_length_of("AAAA////")).to eq 6
  end

  def in_ascii(string)
    String.new(string, encoding: "ASCII-8BIT").freeze
  end
end
