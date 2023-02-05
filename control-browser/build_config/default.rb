MRuby::Build.new("default") do |conf|
  conf.toolchain :gcc

  conf.cc.command = "zig cc"
  conf.linker.command = "zig cc"

  conf.gembox 'default'
end
