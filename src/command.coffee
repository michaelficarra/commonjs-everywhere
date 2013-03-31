fs = require 'fs'
path = require 'path'

escodegen = require 'escodegen'
Jedediah = require 'jedediah'
CJSEverywhere = require './index'

escodegenDefaultFormat =
  indent:
    style: '  '
    base: 0
  renumber: yes
  hexadecimal: yes
  quotes: 'auto'
  parentheses: no
escodegenCompactFormat =
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

optionParser = new Jedediah

optionParser.addOption 'help', off, 'display this help message'
optionParser.addOption 'minify', 'm', off, 'minify output'
optionParser.addOption 'ignore-missing', off, 'continue without error when dependency resolution fails'
optionParser.addOption 'watch', 'w', off, 'watch input files/dependencies for changes and rebuild bundle'
optionParser.addOption 'verbose', 'v', off, 'verbose output sent to stderr'
optionParser.addParameter 'export', 'x', 'NAME', 'export the given entry module as NAME'
optionParser.addParameter 'output', 'o', 'FILE', 'output to FILE instead of stdout'
optionParser.addParameter 'root', 'r', 'DIR', 'unqualified requires are relative to DIR (default: cwd)'
optionParser.addParameter 'source-map-file', 'FILE', 'output a source map to FILE'

[options, positionalArgs] = optionParser.parse process.argv
options.ignoreMissing = options['ignore-missing']
options.sourceMapFile = options['source-map-file']

if options.help
  $0 = if process.argv[0] is 'node' then process.argv[1] else process.argv[0]
  $0 = path.basename $0
  console.log "
  Usage: #{$0} OPT* path/to/entry-file.ext OPT*

#{optionParser.help()}
"
  process.exit 0

unless positionalArgs.length is 1
  throw new Error "wrong number of entry points given; expected 1"

if options.watch and not options.output
  console.error '--watch requires --ouput'
  process.exit 1

destination = if options.output then path.dirname options.output else process.cwd()

root = if options.root then path.resolve options.root else process.cwd()
originalEntryPoint = positionalArgs[0]

build = (entryPoint, processed = {}) ->
  newDeps = CJSEverywhere.traverseDependenciesSync entryPoint, root, options
  processed[file] = newDeps[file] for own file of newDeps
  bundled = CJSEverywhere.bundle processed, originalEntryPoint, root, options

  if options.minify
    esmangle = require 'esmangle'
    bundled = esmangle.mangle (esmangle.optimize bundled), destructive: yes

  {code, map} = escodegen.generate bundled,
    comment: no
    sourceMap: yes
    sourceMapWithCode: yes
    sourceMapRoot: path.relative(destination, root) || '.'
    format: if options.minify then escodegenCompactFormat else escodegenDefaultFormat

  if options.sourceMapFile
    fs.writeFileSync options.sourceMapFile, "#{map}"
    code += "\n/*\n//@ sourceMappingURL=#{options.sourceMapFile}\n*/"

  if options.output
    fs.writeFileSync options.output, code
  else
    process.stdout.write "#{code}\n"

  processed

startBuild = ->
  processed = build originalEntryPoint

  if options.watch
    watching = []
    do startWatching = (processed) ->
      for own file of processed when file not in watching then do (file) ->
        watching.push file
        fs.watchFile file, {persistent: yes, interval: 500}, (curr, prev) ->
          console.error "Rebuilding bundle starting at file #{file}"
          startWatching (processed = build file, processed)
          return

if originalEntryPoint is '-'
  # support reading input from stdin
  stdinput = ''
  process.stdin.on 'data', (data) -> stdinput += data
  process.stdin.on 'end', ->
    originalEntryPoint = (require 'mktemp').createFileSync 'temp-XXXXXXXXX.js'
    fs.writeFileSync originalEntryPoint, stdinput
    process.on 'exit', -> fs.unlinkSync originalEntryPoint
    do startBuild
  process.stdin.setEncoding 'utf8'
  do process.stdin.resume
else
  do startBuild
