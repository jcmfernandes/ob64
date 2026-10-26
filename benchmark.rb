require "benchmark/ips"

# Ruby's own, captured before ob64/core_ext patches them.
NATIVE_PACK = Array.instance_method(:pack)
NATIVE_UNPACK1 = String.instance_method(:unpack1)

require "ob64"
require "ob64/core_ext"

$run_base64_benchmark = true
$run_uu_benchmark = true

def to_size(bytes)
  bytes >= 2**20 ? "#{bytes / 2**20} MB" : "#{bytes / 2**10} kB"
end

def each_size
  [1 * 2**10, 4 * 2**10, 64 * 2**10, 1 * 2**20, 10 * 2**20, 64 * 2**20].each do |size|
    puts "\n\n#{"=" * 60}\nbenchmark with block size #{to_size(size)}"
    yield Random.bytes(size)
  end
end

# Compares reports, label => block
def compare(reports)
  GC.start
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    reports.each { |label, block| x.report(label, &block) }

    x.compare!(order: :baseline)
  end
end

each_size do |bin|
  m0 = NATIVE_PACK.bind_call([bin], "m0")
  urlsafe = m0.tr("+/", "-_")
  m = NATIVE_PACK.bind_call([bin], "m")

  compare(
    "Ruby pack(\"m0\")" => -> { NATIVE_PACK.bind_call([bin], "m0") },
    "ob64 Base64.encode" => -> { Ob64::Base64.encode(bin) },
    "ob64 pack(\"m0\")" => -> { [bin].pack("m0") }
  )
  compare(
    "Ruby unpack1(\"m0\")" => -> { NATIVE_UNPACK1.bind_call(m0, "m0") },
    "ob64 Base64.decode" => -> { Ob64::Base64.decode(m0) },
    "ob64 unpack1(\"m0\")" => -> { m0.unpack1("m0") }
  )
  compare(
    "Ruby pack(\"m0\").tr" => -> { NATIVE_PACK.bind_call([bin], "m0").tr("+/", "-_") },
    "ob64 Base64.urlsafe_encode" => -> { Ob64::Base64.urlsafe_encode(bin) }
  )
  compare(
    "Ruby tr.unpack1(\"m0\")" => -> { NATIVE_UNPACK1.bind_call(urlsafe.tr("-_", "+/"), "m0") },
    "ob64 Base64.urlsafe_decode" => -> { Ob64::Base64.urlsafe_decode(urlsafe) }
  )
  compare(
    "Ruby pack(\"m\")" => -> { NATIVE_PACK.bind_call([bin], "m") },
    "ob64 pack(\"m\")" => -> { [bin].pack("m") }
  )
  compare(
    "Ruby unpack1(\"m\")" => -> { NATIVE_UNPACK1.bind_call(m, "m") },
    "ob64 unpack1(\"m\")" => -> { m.unpack1("m") }
  )
end if $run_base64_benchmark

each_size do |bin|
  u = NATIVE_PACK.bind_call([bin], "u")

  compare(
    "Ruby pack(\"u\")" => -> { NATIVE_PACK.bind_call([bin], "u") },
    "ob64 UU.encode" => -> { Ob64::UU.encode(bin) },
    "ob64 pack(\"u\")" => -> { [bin].pack("u") }
  )
  compare(
    "Ruby unpack1(\"u\")" => -> { NATIVE_UNPACK1.bind_call(u, "u") },
    "ob64 UU.decode" => -> { Ob64::UU.decode(u) },
    "ob64 unpack1(\"u\")" => -> { u.unpack1("u") }
  )
end if $run_uu_benchmark
