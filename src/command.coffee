fs = require 'fs'
path = require 'path'

escodegen = require 'escodegen'
Jedediah = require 'jedediah'
{btoa} = require 'Base64'

CJSEverywhere = require './module'

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
optionParser.addOption 'node', on, 'include process object; emulate node environment; default: on'
optionParser.addOption 'minify', 'm', off, 'minify output'
optionParser.addOption 'ignore-missing', off, 'continue without error when dependency resolution fails'
optionParser.addOption 'inline-sources', on, 'include source content in generated source maps; default: on'
optionParser.addOption 'inline-source-map', off, 'include the source map as a data URI in the generated bundle'
optionParser.addOption 'watch', 'w', off, 'watch input files/dependencies for changes and rebuild bundle'
optionParser.addOption 'verbose', 'v', off, 'verbose output sent to stderr'
optionParser.addParameter 'export', 'x', 'NAME', 'export the given entry module as NAME'
optionParser.addParameter 'output', 'o', 'FILE', 'output to FILE instead of stdout'
optionParser.addParameter 'root', 'r', 'DIR', 'unqualified requires are relative to DIR; default: cwd'
optionParser.addParameter 'source-map', 's', 'FILE', 'output a source map to FILE'
optionParser.addListParameter 'alias', 'a', 'ALIAS:TO', 'replace requires of file identified by ALIAS with TO'
optionParser.addListParameter 'handler', 'h', 'EXT:MODULE', 'handle files with extension EXT with module MODULE'

[options, positionalArgs] = optionParser.parse process.argv
options.ignoreMissing = options['ignore-missing']
options.sourceMap = options['source-map']
options.inlineSources = options['inline-sources']
options.inlineSourceMap = options['inline-source-map']

options.aliases = {}
for aliasPair in options.alias
  match = aliasPair.match /([^:]+):(.*)/ ? []
  if match? then options.aliases[match[1]] = match[2]
  else
    console.error "invalid alias: #{aliasPair}"
    process.exit 1

options.handlers = {}
for handlerPair in options.handler
  match = handlerPair.match /([^:]+):(.*)/ ? []
  if match? then do (ext = ".#{match[1]}", mod = match[2]) ->
    options.handlers[ext] = require mod
  else
    console.error "invalid handler: #{handlerPair}"
    process.exit 1


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
  console.error 'wrong number of entry points given; expected 1'
  process.exit 1

root = if options.root then path.resolve options.root else process.cwd()
originalEntryPoint = positionalArgs[0]

if options.deps
  deps = CJSEverywhere.traverseDependencies originalEntryPoint, root, options
  console.log dep.canonicalName for own _, dep of deps
  process.exit 0

if options.watch and not options.output
  console.error '--watch requires --ouput'
  process.exit 1

build = (entryPoint, processed = {}) ->
  try
    newDeps = CJSEverywhere.traverseDependencies entryPoint, root, options
    if options.watch
      console.error "built #{dep.canonicalName} (#{options.cache[filename]})" for own filename, dep of newDeps
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

  if (options.sourceMap or options.inlineSourceMap) and options.inlineSources
    for own filename, {canonicalName, fileContents} of processed
      map.setSourceContent canonicalName, fileContents

  if options.sourceMap
    fs.writeFileSync options.sourceMap, "#{map}"
    sourceMappingUrl =
      if options.output
        path.relative (path.dirname options.output), options.sourceMap
      else options.sourceMap
    unless options.inlineSourceMap
      code = "#{code}\n//# sourceMappingURL=#{sourceMappingUrl}"

  if options.inlineSourceMap
    datauri = "data:application/json;charset=utf-8;base64,#{btoa "#{map}"}"
    code = "#{code}\n//# sourceMappingURL=#{datauri}"

  if options.output
    fs.writeFileSync options.output, code
  else
    process.stdout.write "#{code}\n"

  if options.watch or options.verbose
    console.error 'BUNDLE COMPLETE'

  processed

startBuild = ->
  if options.watch
    options.cache = {}
    console.error "BUNDLING starting at #{originalEntryPoint}"

  processed = build originalEntryPoint

  if options.watch
    watching = []
    do startWatching = (processed) ->
      for own file, {canonicalName} of processed when file not in watching then do (file, canonicalName) ->
        watching.push file
        fs.watchFile file, {persistent: yes, interval: 500}, (curr, prev) ->
          ino = if process.platform is 'win32' then curr.ino? else curr.ino
          unless ino
            console.error "WARNING: watched file #{file} has disappeared"
            return
          console.error "REBUNDLING starting at #{canonicalName}"
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
