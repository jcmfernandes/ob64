# frozen_string_literal: true

require "mkmf"

def sys(cmd)
  puts " -- #{cmd}"
  unless ret = xsystem(cmd)
    raise "ERROR: '#{cmd}' failed"
  end
  ret
end

def run_cmake(args)
  pid = Process.spawn("cmake #{args}")
  Process.waitpid(pid)
end

if !find_executable("cmake")
  abort "ERROR: CMake is required to build ob64"
end

MAKE = find_executable("make") || find_executable("gmake")
if !MAKE
  abort "ERROR: make is required to build ob64"
end

CWD = __dir__
LIBBASE64_DIR = File.join(CWD, "..", "..", "vendor", "libbase64")

Dir.chdir(LIBBASE64_DIR) do
  Dir.mkdir("build") unless Dir.exist?("build")

  Dir.chdir("build") do
    run_cmake(".. -DBUILD_SHARED_LIBS=true -DOPENMP=false")
    sys(MAKE)
  end

  $DEFLIBPATH.unshift("#{LIBBASE64_DIR}/build/bin")
  dir_config("base64", "#{LIBBASE64_DIR}/include", "#{LIBBASE64_DIR}/build/bin")
end

unless have_library("base64") && have_header("libbase64.h")
  abort "ERROR: Failed to build libbase64"
end

dir_config("ob64_ext")
create_makefile("ob64_ext")
