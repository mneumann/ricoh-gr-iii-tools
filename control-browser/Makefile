MRUBY_SOURCE_DIR=./mruby-3.1.0
#ZIG_TARGET=aarch64-linux-gnu
#ZIG_TARGET=x86_64-windows-gnu
#MRUBY_CONFIG=./build_config/zig-cross.rb
#MRUBY_CONFIG=./build_config/default.rb

build-all: build-default build-aarch64

build:
	env MRUBY_CONFIG=./build_config/default.rb \
		rake -f ${MRUBY_SOURCE_DIR}/Rakefile

build-aarch64:
	env ZIG_TARGET=aarch64-linux-gnu MRUBY_CONFIG=./build_config/zig-cross.rb \
		rake -f ${MRUBY_SOURCE_DIR}/Rakefile

compile: build
	${MRUBY_SOURCE_DIR}/build/default/bin/mrbc -o server.mrb mrblib/*.rb server.rb

run: compile
	${MRUBY_SOURCE_DIR}/build/default/bin/mruby -b server.mrb

clean:
	rm -rf ${MRUBY_SOURCE_DIR}/build
