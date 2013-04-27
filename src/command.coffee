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

optionParser.addOption 'help', off, 'display this help message and exit'
optionParser.addOption 'version', off, 'display the version number and exit'
optionParser.addOption 'deps', off, 'do not bundle; just list the files that would be bundled'
optionParser.addOption 'node', on, 'include process object; emulate node environment (default: on)'
optionParser.addOption 'minify', 'm', off, 'minify output'
optionParser.addOption 'ignore-missing', off, 'continue without error when dependency resolution fails'
optionParser.addOption 'watch', 'w', off, 'watch input files/dependencies for changes and rebuild bundle'
optionParser.addOption 'verbose', 'v', off, 'verbose output sent to stderr'
optionParser.addParameter 'export', 'x', 'NAME', 'export the given entry module as NAME'
optionParser.addParameter 'output', 'o', 'FILE', 'output to FILE instead of stdout'
optionParser.addParameter 'root', 'r', 'DIR', 'unqualified requires are relative to DIR (default: cwd)'
optionParser.addParameter 'source-map', 's', 'FILE', 'output a source map to FILE'

[options, positionalArgs] = optionParser.parse process.argv
options.ignoreMissing = options['ignore-missing']
options.sourceMap = options['source-map']

if options.help
  $0 = if process.argv[0] is 'node' then process.argv[1] else process.argv[0]
  $0 = path.basename $0
  console.log "
  Usage: #{$0} OPT* path/to/entry-file.ext OPT*

#{optionParser.help()}
"
  process.exit 0

if options.version
  console.log (require '../package.json').version
  process.exit 0

unless positionalArgs.length is 1
  throw new Error "wrong number of entry points given; expected 1"

root = if options.root then path.resolve options.root else process.cwd()
originalEntryPoint = positionalArgs[0]

if options.deps
  deps = CJSEverywhere.traverseDependencies originalEntryPoint, root, options
  console.log (Object.keys deps).sort().map((f) -> path.relative root, f).join '\n'
  process.exit 0

if options.watch and not options.output
  console.error '--watch requires --ouput'
  process.exit 1

build = (entryPoint, processed = {}) ->
  try
    newDeps = CJSEverywhere.traverseDependencies entryPoint, root, options
    if options.watch
      console.error "built #{file} (#{options.cache[file]})" for file in Object.keys newDeps
    processed[file] = newDeps[file] for own file of newDeps
  catch e
    if options.watch then console.error "ERROR: #{e.message}" else throw e
  bundled = CJSEverywhere.bundle processed, originalEntryPoint, root, options

  if options.minify
    esmangle = require 'esmangle'
    bundled = esmangle.mangle (esmangle.optimize bundled), destructive: yes

  {code, map} = escodegen.generate bundled,
    comment: not options.minify
    sourceMap: yes
    sourceMapWithCode: yes
    sourceMapRoot: if options.sourceMap? then (path.relative (path.dirname options.sourceMap), root) or '.'
    format: if options.minify then escodegenCompactFormat else escodegenDefaultFormat

  if options.sourceMap
    fs.writeFileSync options.sourceMap, "#{map}"
    sourceMappingUrl =
      if options.output
        path.relative (path.dirname options.output), options.sourceMap
      else options.sourceMap
    code = "#{code}\n/*\n//@ sourceMappingURL=#{sourceMappingUrl}\n*/"

  if options.output
    fs.writeFileSync options.output, code
  else
    process.stdout.write "#{code}\n"

  processed

startBuild = ->
  if options.watch
    options.cache = {}
    console.error "Building bundle starting at #{originalEntryPoint}"

  processed = build originalEntryPoint

  if options.watch
    watching = []
    do startWatching = (processed) ->
      for own file of processed when file not in watching then do (file) ->
        watching.push file
        fs.watchFile file, {persistent: yes, interval: 500}, (curr, prev) ->
          unless curr.ino
            console.error "WARNING: watched file #{file} has disappeared"
            return
          console.error "Rebuilding bundle starting at #{file}"
          processed = build file, processed
          startWatching processed
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
