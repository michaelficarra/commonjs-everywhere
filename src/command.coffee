fs = require 'fs'
path = require 'path'

escodegen = require 'escodegen'
Jedediah = require 'jedediah'
CJSEverywhere = require './index'

flagSpec = [
]
paramSpec = [
  [['export', 'x'], 'NAME', 'export the given entry module as NAME']
  [['output', 'o'], 'FILE', 'output to FILE instead of stdout']
  [['root',   'r'], 'DIR', 'unqualified requires are relative to DIR (default: cwdv)']
]
optionParser = new Jedediah flagSpec, paramSpec
[options, positionalArgs] = optionParser.parse process.argv

unless positionalArgs.length is 1
  throw new Error "wrong number of entry points given; expected 1"

root = if options.root then path.resolve options.root else process.cwd()
combined = CJSEverywhere.build positionalArgs[0], options.export, root
js = escodegen.generate combined

if options.output
  fs.writeFileSync options.output, js
else
  process.stdout.write "#{js}\n"
