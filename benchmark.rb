require "benchmark/ips"
require "securerandom"

NATIVE_PACK = Array.instance_method(:pack)
NATIVE_UNPACK1 = String.instance_method(:unpack1)

require "ob64"
require "ob64/core_ext"
require "base64"

$run_encode_benchmark = true
$run_decode_benchmark = true
$run_urlsafe_encode_benchmark = true
$run_urlsafe_decode_benchmark = true
$run_m_benchmark = true
$run_u_benchmark = true

def to_size(bytes)
  bytes >= 2**20 ? "#{bytes / 2**20} MB" : "#{bytes / 2**10} kB"
end

def each_block
  [
    [1, :kb],
    [4, :kb],
    [64, :kb],
    [1, :mb],
    [10, :mb],
    [64, :mb]
  ].each do |(n, unit)|
    yield(n * 2**({kb: 10, mb: 20}.fetch(unit)))
  end
end

def benchmark(setup_block)
  each_block do |size|
    setup_block.call(size)
    GC.start
    puts "\n\n#{"=" * 60}\nbenchmark with block size #{to_size(size)}"
    yield
  end
end

def encode_benchmark(&block)
  benchmark(
    lambda { |size| $unencoded = File.open("/dev/urandom") { |f| f.read(size) } },
    &block
  )
end

def decode_benchmark(&block)
  benchmark(
    lambda { |size| $encoded = SecureRandom.base64(size) },
    &block
  )
end

encode_benchmark do
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("base64 .strict_encode64") do
      Base64.strict_encode64($unencoded)
    end

    x.report("ob64 .encode") do
      Ob64::Base64.encode($unencoded)
    end

    x.compare!
  end
end if $run_encode_benchmark

decode_benchmark do
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("base64 .strict_decode64") do
      Base64.strict_decode64($encoded)
    end

    x.report("ob64 .decode") do
      Ob64::Base64.decode($encoded)
    end

    x.compare!
  end
end if $run_decode_benchmark

encode_benchmark do
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("base64 .urlsafe_encode64") do
      Base64.urlsafe_encode64($unencoded)
    end

    x.report("ob64 .urlsafe_encode") do
      Ob64::Base64.urlsafe_encode($unencoded)
    end

    x.compare!
  end
end if $run_urlsafe_encode_benchmark

decode_benchmark do
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("base64 .urlsafe_decode64") do
      Base64.urlsafe_decode64($encoded)
    end

    x.report("ob64 .urlsafe_decode") do
      Ob64::Base64.urlsafe_decode($encoded)
    end

    x.compare!
  end
end if $run_urlsafe_decode_benchmark

encode_benchmark do
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("native pack(\"m\")") do
      NATIVE_PACK.bind_call([$unencoded], "m")
    end

    x.report("ob64 pack(\"m\")") do
      [$unencoded].pack("m")
    end

    x.compare!
  end

  $encoded_m = NATIVE_PACK.bind_call([$unencoded], "m")
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("native unpack1(\"m\")") do
      NATIVE_UNPACK1.bind_call($encoded_m, "m")
    end

    x.report("ob64 unpack1(\"m\")") do
      $encoded_m.unpack1("m")
    end

    x.compare!
  end
end if $run_m_benchmark

encode_benchmark do
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("native pack(\"u\")") do
      NATIVE_PACK.bind_call([$unencoded], "u")
    end

    x.report("ob64 UU.encode") do
      Ob64::UU.encode($unencoded)
    end

    x.compare!
  end

  $encoded_u = NATIVE_PACK.bind_call([$unencoded], "u")
  Benchmark.ips do |x|
    x.time = 5
    x.warmup = 2

    x.report("native unpack1(\"u\")") do
      NATIVE_UNPACK1.bind_call($encoded_u, "u")
    end

    x.report("ob64 UU.decode") do
      Ob64::UU.decode($encoded_u)
    end

    x.compare!
  end
end if $run_u_benchmark
