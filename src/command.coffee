fs = require 'fs'
path = require 'path'

escodegen = require 'escodegen'
nopt = require 'nopt'
{btoa} = require 'Base64'

CJSEverywhere = require './module'
relativeResolve = require './relative-resolve'

escodegenFormat =
  indent:
    style: '  '
    base: 0
  renumber: yes
  hexadecimal: yes
  quotes: 'auto'
  parentheses: no

knownOpts = {}
# options
knownOpts[opt] = Boolean for opt in [
  'amd', 'deps', 'help', 'ignore-missing', 'inline-source-map',
  'inline-sources', 'minify', 'node', 'verbose', 'watch'
]
# parameters
knownOpts[opt] = String for opt in ['export', 'output', 'root', 'source-map']
# list parameters
knownOpts[opt] = [String, Array] for opt in ['alias', 'handler']

optAliases =
  a: '--alias'
  h: '--handler'
  m: '--minify'
  o: '--output'
  r: '--root'
  s: '--source-map'
  v: '--verbose'
  w: '--watch'
  x: '--export'

options = nopt knownOpts, optAliases, process.argv, 2
positionalArgs = options.argv.remain
delete options.argv

# default values
options.node ?= on
options['inline-sources'] ?= on
options.alias ?= []
options.handler ?= []

options.ignoreMissing = options['ignore-missing']
options.sourceMap = options['source-map']
options.inlineSources = options['inline-sources']
options.inlineSourceMap = options['inline-source-map']

if options.help
  $0 = if process.argv[0] is 'node' then process.argv[1] else process.argv[0]
  $0 = path.basename $0
  console.log "
  Usage: #{$0} OPT* path/to/entry-file.ext OPT*

  -a, --alias ALIAS:TO      replace requires of file identified by ALIAS with TO
  -h, --handler EXT:MODULE  handle files with extension EXT with module MODULE
  -m, --minify              minify output
  -o, --output FILE         output to FILE instead of stdout
  -r, --root DIR            unqualified requires are relative to DIR; default: cwd
  -s, --source-map FILE     output a source map to FILE
  -v, --verbose             verbose output sent to stderr
  -w, --watch               watch input files/dependencies for changes and rebuild bundle
  -x, --export NAME         export the given entry module as NAME
  --deps                    do not bundle; just list the files that would be bundled
  --help                    display this help message and exit
  --ignore-missing          continue without error when dependency resolution fails
  --inline-source-map       include the source map as a data URI in the generated bundle
  --inline-sources          include source content in generated source maps; default: on
  --node                    include process object; emulate node environment; default: on
  --version                 display the version number and exit
"
  process.exit 0

if options.version
  console.log (require '../package.json').version
  process.exit 0

unless positionalArgs.length is 1
  console.error 'wrong number of entry points given; expected 1'
  process.exit 1

options.aliases = {}
for aliasPair in options.alias
  match = aliasPair.match /([^:]+):(.*)/ ? []
  if match? then options.aliases[match[1]] = match[2]
  else
    console.error "invalid alias: #{aliasPair}"
    process.exit 1
delete options.alias

root = if options.root then path.resolve options.root else process.cwd()
originalEntryPoint = positionalArgs[0]

options.handlers = {}
for handlerPair in options.handler
  match = handlerPair.match /([^:]+):(.*)/ ? []
  if match? then do (ext = ".#{match[1]}", mod = match[2]) ->
    resolved = relativeResolve
      extensions: Object.keys require.extensions
      root: root
      cwd: process.cwd()
      path: mod
    options.handlers[ext] = require resolved.filename
  else
    console.error "invalid handler: #{handlerPair}"
    process.exit 1
delete options.handler

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
    format: if options.minify then escodegen.FORMAT_MINIFY else escodegenFormat

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
