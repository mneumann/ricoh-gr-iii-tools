ZIG_TARGET = ENV['ZIG_TARGET'] || raise("Please define ZIG_TARGET env")

MRuby::CrossBuild.new("zig-cross-#{ZIG_TARGET}") do |conf|
  conf.toolchain :gcc

  conf.cc.command = "zig cc -target #{ZIG_TARGET}"
  conf.linker.command = "zig cc -target #{ZIG_TARGET}"

  conf.gembox 'default'

  conf.test_runner.command = 'env'
end
