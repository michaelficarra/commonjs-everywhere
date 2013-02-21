default: all

SRC = $(shell find src -name "*.coffee" -type f | sort)
LIB = $(SRC:src/%.coffee=lib/%.js)

COFFEE=node_modules/.bin/coffee --js
MOCHA=node_modules/.bin/mocha --compilers coffee:coffee-script-redux -u tdd

all: build test
build: $(LIB)

lib:
	mkdir lib/
lib/%.js: src/%.coffee lib
	$(COFFEE) <"$<" >"$@"

.PHONY: test
loc:
	wc -l src/*
test:
	$(MOCHA) -R dot test
clean:
	rm -rf lib
