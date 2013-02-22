fs = require 'fs'
path = require 'path'

escodegen = require 'escodegen'
Jedediah = require 'jedediah'
CJSEverywhere = require './index'

optionParser = new Jedediah

optionParser.addOption 'help', off, 'display this help message'
optionParser.addParameter 'export', 'x', 'NAME', 'export the given entry module as NAME'
optionParser.addParameter 'output', 'o', 'FILE', 'output to FILE instead of stdout'
optionParser.addParameter 'root', 'r', 'DIR', 'unqualified requires are relative to DIR (default: cwdv)'

[options, positionalArgs] = optionParser.parse process.argv

if options.help
  $0 = if process.argv[0] is 'node' then process.argv[1] else process.argv[0]
  $0 = path.basename $0
  console.log "
  Usage: #{$0} OPT* path/to/entry-file.{js,coffee}

#{optionParser.help()}
"
  process.exit 0

unless positionalArgs.length is 1
  throw new Error "wrong number of entry points given; expected 1"

root = if options.root then path.resolve options.root else process.cwd()
combined = CJSEverywhere.build positionalArgs[0], options.export, root
js = escodegen.generate combined

if options.output
  fs.writeFileSync options.output, js
else
  process.stdout.write "#{js}\n"
