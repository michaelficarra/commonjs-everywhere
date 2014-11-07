default: build

SRC = $(shell find src -name '*.coffee' -type f | sort)
LIB = $(SRC:src/%.coffee=lib/%.js)

COFFEE=node_modules/.bin/coffee --js
MOCHA=node_modules/.bin/mocha --compilers coffee:coffee-script-redux/register -r test-setup.coffee -u tdd
XYZ=node_modules/.bin/xyz --repo git@github.com:michaelficarra/commonjs-everywhere.git --script changelog.sh

all: build test
build: $(LIB)

lib/%.js: src/%.coffee
	@mkdir -p '$(@D)'
	$(COFFEE) <'$<' >'$@'

.PHONY: default all build release-patch release-minor release-major test loc clean

release-major release-minor release-patch: build test
	@$(XYZ) --increment $(@:release-%=%)

test:
	$(MOCHA) -R dot test/*.coffee

loc:
	@wc -l src/*
clean:
	@rm -rf lib
