MRuby::Build.new("default") do |conf|
  conf.toolchain :gcc

  conf.cc.command = "zig cc"
  conf.linker.command = "zig cc"

  conf.gem mgem: 'mruby-process'

  conf.gembox 'default'
end
