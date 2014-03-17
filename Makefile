default: build

CHANGELOG=CHANGELOG

SRC = $(shell find src -name '*.coffee' -type f | sort)
LIB = $(SRC:src/%.coffee=lib/%.js)

COFFEE=node_modules/.bin/coffee --js
MOCHA=node_modules/.bin/mocha --compilers coffee:coffee-script-redux/register -r test-setup.coffee -u tdd
SEMVER=node_modules/.bin/semver

all: build test
build: $(LIB)

lib/%.js: src/%.coffee
	@mkdir -p '$(@D)'
	$(COFFEE) <'$<' >'$@'

.PHONY: default all build release-patch release-minor release-major test loc clean

VERSION = $(shell node -p 'require("./package.json").version')
release-patch: NEXT_VERSION = $(shell $(SEMVER) -i patch $(VERSION))
release-minor: NEXT_VERSION = $(shell $(SEMVER) -i minor $(VERSION))
release-major: NEXT_VERSION = $(shell $(SEMVER) -i major $(VERSION))

release-patch release-minor release-major: build test
	@printf 'Current version is $(VERSION). This will publish version $(NEXT_VERSION). Press [enter] to continue.' >&2
	@read
	./changelog.sh 'v$(NEXT_VERSION)' >'$(CHANGELOG)'
	node -e '\
		var j = require("./package.json");\
		j.version = "$(NEXT_VERSION)";\
		var s = JSON.stringify(j, null, 2) + "\n";\
		require("fs").writeFileSync("./package.json", s);'
	git commit package.json '$(CHANGELOG)' -m 'Version $(NEXT_VERSION)'
	git tag -a 'v$(NEXT_VERSION)' -m 'Version $(NEXT_VERSION)'
	git push origin refs/heads/master 'refs/tags/v$(NEXT_VERSION)'
	npm publish

test:
	$(MOCHA) -R dot test/*.coffee

loc:
	@wc -l src/*
clean:
	@rm -rf lib
