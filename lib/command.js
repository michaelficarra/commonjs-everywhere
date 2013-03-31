(function() {
  var $0, CJSEverywhere, Jedediah, build, escodegen, escodegenCompactFormat, escodegenDefaultFormat, fs, optionParser, options, originalEntryPoint, path, positionalArgs, root, startBuild, stdinput, _ref,
    __hasProp = {}.hasOwnProperty,
    __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  fs = require('fs');

  path = require('path');

  escodegen = require('escodegen');

  Jedediah = require('jedediah');

  CJSEverywhere = require('./index');

  escodegenDefaultFormat = {
    indent: {
      style: '  ',
      base: 0
    },
    renumber: true,
    hexadecimal: true,
    quotes: 'auto',
    parentheses: false
  };

  escodegenCompactFormat = {
    indent: {
      style: '',
      base: 0
    },
    renumber: true,
    hexadecimal: true,
    quotes: 'auto',
    escapeless: true,
    compact: true,
    parentheses: false,
    semicolons: false
  };

  optionParser = new Jedediah;

  optionParser.addOption('help', false, 'display this help message');

  optionParser.addOption('minify', 'm', false, 'minify output');

  optionParser.addOption('ignore-missing', false, 'continue without error when dependency resolution fails');

  optionParser.addOption('watch', 'w', false, 'watch input files/dependencies for changes and rebuild bundle');

  optionParser.addOption('verbose', 'v', false, 'verbose output sent to stderr');

  optionParser.addParameter('export', 'x', 'NAME', 'export the given entry module as NAME');

  optionParser.addParameter('output', 'o', 'FILE', 'output to FILE instead of stdout');

  optionParser.addParameter('root', 'r', 'DIR', 'unqualified requires are relative to DIR (default: cwd)');

  optionParser.addParameter('source-map-file', 'FILE', 'output a source map to FILE');

  _ref = optionParser.parse(process.argv), options = _ref[0], positionalArgs = _ref[1];

  options.ignoreMissing = options['ignore-missing'];

  options.sourceMapFile = options['source-map-file'];

  if (options.help) {
    $0 = process.argv[0] === 'node' ? process.argv[1] : process.argv[0];
    $0 = path.basename($0);
    console.log("  Usage: " + $0 + " OPT* path/to/entry-file.ext OPT*" + (optionParser.help()) + "");
    process.exit(0);
  }

  if (positionalArgs.length !== 1) {
    throw new Error("wrong number of entry points given; expected 1");
  }

  if (options.watch && !options.output) {
    console.error('--watch requires --ouput');
    process.exit(1);
  }

  root = options.root ? path.resolve(options.root) : process.cwd();

  originalEntryPoint = positionalArgs[0];

  build = function(entryPoint, processed) {
    var bundled, code, esmangle, file, map, newDeps, _ref1;

    if (processed == null) {
      processed = {};
    }
    newDeps = CJSEverywhere.traverseDependenciesSync(entryPoint, root, options);
    for (file in newDeps) {
      if (!__hasProp.call(newDeps, file)) continue;
      processed[file] = newDeps[file];
    }
    bundled = CJSEverywhere.bundle(processed, originalEntryPoint, root, options);
    if (options.minify) {
      esmangle = require('esmangle');
      bundled = esmangle.mangle(esmangle.optimize(bundled), {
        destructive: true
      });
    }
    _ref1 = escodegen.generate(bundled, {
      comment: false,
      sourceMap: true,
      sourceMapWithCode: true,
      sourceMapRoot: path.relative('.', root) || '.',
      format: options.minify ? escodegenCompactFormat : escodegenDefaultFormat
    }), code = _ref1.code, map = _ref1.map;
    if (options.sourceMapFile) {
      fs.writeFileSync(options.sourceMapFile, "" + map);
      code += "\n/*\n//@ sourceMappingURL=" + options.sourceMapFile + "\n*/";
    }
    if (options.output) {
      fs.writeFileSync(options.output, code);
    } else {
      process.stdout.write("" + code + "\n");
    }
    return processed;
  };

  startBuild = function() {
    var processed, startWatching, watching;

    processed = build(originalEntryPoint);
    if (options.watch) {
      watching = [];
      return (startWatching = function(processed) {
        var file, _results;

        _results = [];
        for (file in processed) {
          if (!__hasProp.call(processed, file)) continue;
          if (__indexOf.call(watching, file) < 0) {
            _results.push((function(file) {
              watching.push(file);
              return fs.watchFile(file, {
                persistent: true,
                interval: 500
              }, function(curr, prev) {
                console.error("Rebuilding bundle starting at file " + file);
                startWatching((processed = build(file, processed)));
              });
            })(file));
          }
        }
        return _results;
      })(processed);
    }
  };

  if (originalEntryPoint === '-') {
    stdinput = '';
    process.stdin.on('data', function(data) {
      return stdinput += data;
    });
    process.stdin.on('end', function() {
      originalEntryPoint = (require('mktemp')).createFileSync('temp-XXXXXXXXX.js');
      fs.writeFileSync(originalEntryPoint, stdinput);
      process.on('exit', function() {
        return fs.unlinkSync(originalEntryPoint);
      });
      return startBuild();
    });
    process.stdin.setEncoding('utf8');
    process.stdin.resume();
  } else {
    startBuild();
  }

}).call(this);
