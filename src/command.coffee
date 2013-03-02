fs = require 'fs'
path = require 'path'

escodegen = require 'escodegen'
Jedediah = require 'jedediah'
CJSEverywhere = require './index'

optionParser = new Jedediah

optionParser.addOption 'help', off, 'display this help message'
optionParser.addOption 'minify', 'm', off, 'minify output'
optionParser.addOption 'verbose', 'v', off, 'verbose output sent to stderr'
optionParser.addParameter 'export', 'x', 'NAME', 'export the given entry module as NAME'
optionParser.addParameter 'output', 'o', 'FILE', 'output to FILE instead of stdout'
optionParser.addParameter 'root', 'r', 'DIR', 'unqualified requires are relative to DIR (default: cwd)'
optionParser.addParameter 'source-map-file', 'FILE', 'output a source map to FILE'

[options, positionalArgs] = optionParser.parse process.argv

if options.help
  $0 = if process.argv[0] is 'node' then process.argv[1] else process.argv[0]
  $0 = path.basename $0
  console.log "
  Usage: #{$0} OPT* path/to/entry-file.{js,coffee} OPT*

#{optionParser.help()}
"
  process.exit 0

unless positionalArgs.length is 1
  throw new Error "wrong number of entry points given; expected 1"

root = if options.root then path.resolve options.root else process.cwd()
combined = CJSEverywhere.cjsify positionalArgs[0], root, options

escodegenFormat =
  indent:
    style: '  '
    base: 0
  renumber: yes
  hexadecimal: yes
  quotes: 'auto'
  parentheses: no

if options.minify
  esmangle = require 'esmangle'
  combined = esmangle.mangle (esmangle.optimize combined), destructive: yes
  escodegenFormat =
    indent:
      style: ''
      base: 0
    renumber: yes
    hexadecimal: yes
    quotes: 'auto'
    escapeless: yes
    compact: yes
    parentheses: no
    semicolons: no

{code, map} = escodegen.generate combined,
  comment: no
  sourceMap: yes
  sourceMapWithCode: yes
  sourceMapRoot: root
  format: escodegenFormat


if options['source-map-file']
  fs.writeFileSync options['source-map-file'], "#{map}"
  code += "\n/*\n//@ sourceMappingURL=#{options['source-map-file']}\n*/"

if options.output
  fs.writeFileSync options.output, code
else
  process.stdout.write "#{code}\n"
