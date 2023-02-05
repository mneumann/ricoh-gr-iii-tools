MRUBY_SOURCE_DIR=./mruby-3.1.0
#ZIG_TARGET=aarch64-linux-gnu
#ZIG_TARGET=x86_64-windows-gnu
#MRUBY_CONFIG=./build_config/zig-cross.rb
#MRUBY_CONFIG=./build_config/default.rb
FETCH?=fetch

mruby-src! ${MRUBY_SOURCE_DIR}

${MRUBY_SOURCE_DIR}: mruby-3.1.0.zip
	unzip mruby-3.1.0.zip

mruby-3.1.0.zip:
	${FETCH} -o mruby-3.1.0.zip https://github.com/mruby/mruby/archive/3.1.0.zip

build-all: build-default build-aarch64

build: mruby-src
	env MRUBY_CONFIG=./build_config/default.rb \
		rake -f ${MRUBY_SOURCE_DIR}/Rakefile

build-aarch64: mruby-src
	env ZIG_TARGET=aarch64-linux-gnu MRUBY_CONFIG=./build_config/zig-cross.rb \
		rake -f ${MRUBY_SOURCE_DIR}/Rakefile

compile: build
	${MRUBY_SOURCE_DIR}/build/default/bin/mrbc -o server.mrb mrblib/*.rb server.rb

run: compile
	${MRUBY_SOURCE_DIR}/build/default/bin/mruby -b server.mrb

clean:
	rm -rf ${MRUBY_SOURCE_DIR}/build

clean-all: clean
	rm -rf ${MRUBY_SOURCE_DIR}
	rm -f mruby-3.1.0.zip
