.DEFAULT_GOAL := build
#INSTALL_SCRIPT=./install.sh
#BIN_FILE=./mis-arbolitos

build:
	zig build

run:
	zig run

clean:
	rm -rf .zig-cache zig-out

