fs = require 'fs'
path = require 'path'
nopt = require 'nopt'
_ = require 'lodash'

Powerbuild = require './index'
buildCache = require '../src/build-cache'
traverseDependencies = require './traverse-dependencies'

knownOpts = {}
# options
knownOpts[opt] = Boolean for opt in [
  'deps', 'help', 'ignore-missing', 'inline-source-map', 'inline-sources',
  'minify', 'compress', 'node', 'verbose', 'watch', 'cache-path',
  '--disable-disk-cache', '--npm-source-maps'
]
# parameters
knownOpts[opt] = String for opt in ['export', 'output', 'root', 'source-map']
# list parameters
knownOpts[opt] = [String, Array] for opt in ['alias', 'handler']

optAliases =
  a: '--alias'
  h: '--handler'
  m: '--minify'
  c: '--compress'
  o: '--output'
  r: '--root'
  s: '--source-map'
  v: '--verbose'
  w: '--watch'
  x: '--export'

options = nopt knownOpts, optAliases, process.argv, 2
options.entryPoints = entryPoints = _.uniq options.argv.remain
delete options.argv

# default values
options.ignoreMissing = options['ignore-missing']
options.sourceMap = options['source-map']
options.inlineSources = options['inline-sources']
options.inlineSourceMap = options['inline-source-map']
options.cachePath = options['cache-path']
options.disableDiskCache = options['cache-path']
options.npmSourceMaps = options['npm-source-maps']

if options.help
  $0 = if process.argv[0] is 'node' then process.argv[1] else process.argv[0]
  $0 = path.basename $0
  console.log "
  Usage: #{$0} OPT* ENTRY_FILE+ OPT*

  -a, --alias ALIAS:TO      replace requires of file identified by ALIAS with TO
  -h, --handler EXT:MODULE  handle files with extension EXT with module MODULE
  -m, --minify              minify output using uglify.js
  -c, --compress            Compress/optimize code when minifying
                            (automatically enabled by this option). Enabling
                            will break the generated source map.
  -o, --output FILE         output to FILE instead of stdout
  -r, --root DIR            unqualified requires are relative to DIR; default: cwd
  -s, --source-map FILE     output a source map to FILE
  -v, --verbose             verbose output sent to stderr
  -w, --watch               watch input files/dependencies for changes and rebuild bundle
  -x, --export NAME         export the last given entry module as NAME
  --deps                    do not bundle; just list the files that would be bundled
  --help                    display this help message and exit
  --ignore-missing          continue without error when dependency resolution fails
  --inline-source-map       include the source map as a data URI in the generated bundle
  --inline-sources          include source content in generated source maps; default: on
  --node                    if needed by any module, emulate a node.js 
                            environment by including globals such as Buffer,
                            process and setImmediate; default: on
  --cache-path              file where to read/write a json-encoded cache that
                            is used for fast, incremental builds.
                            default: '.powerbuild-cache~' in the current
                            directory
  --disable-disk-cache      disables persistence of incremental build cache
                            to disk. Incremental build will only work with the
                            --watch option
  --npm-source-maps         add mappings for npm modules in the resulting
                            source map(significantly increases the build time)
  --version                 display the version number and exit
"
  process.exit 0

if options.version
  console.log (require '../package.json').version
  process.exit 0

if options.deps
  options.processed = {}
  traverseDependencies options
  console.log dep.canonicalName for own _, dep of options.processed
  process.exit 0

if options.watch and not options.output
  console.error '--watch requires --output'
  process.exit 1

options.alias ?= []
options.aliases = {}

for aliasPair in options.alias
  if match = aliasPair.match /([^:]+):(.*)/ ? []
    options.aliases[match[1]] = match[2]
  else
    throw new Error "invalid alias: #{aliasPair}"

options.handler ?= []
options.handlers = {}

for handlerPair in options.handler
  if match = handlerPair.match /([^:]+):(.*)/ ? []
    options.handlers[match[1]] = require match[2]
  else
    throw new Error "invalid handler: #{handlerPair}"


buildBundle = ->
  start = new Date().getTime()
  {code, map} = build.bundle()

  if build.output
    fs.writeFileSync build.output, code
    console.error("Created #{build.output}")
    if build.sourceMap
      console.error("Created #{build.sourceMap}")
      fs.writeFileSync build.sourceMap, "#{map}"
    console.error("Completed in #{new Date().getTime() - start} ms")
  else
    process.stdout.write "#{code}\n"

if not options.disableDiskCache
  cache = buildCache(options.cachePath)
  options.processed = cache.processed
  options.uids = cache.uids

build = new Powerbuild options

startBuild = ->
  buildBundle()

  if options.watch
    process.on 'SIGINT', process.exit
    process.on 'SIGTERM', process.exit

    console.error("Watching for changes...")
    # Flush the cache when the user presses CTRL+C or the process is
    # terminated from outside
    watching = {}
    building = false
    for own file of build.processed when file not of watching then do (file) ->
      watching[file] = true
      fs.watchFile file, {persistent: yes, interval: 500}, (curr, prev) ->
        if building then return
        console.error("File '#{file}' as changed, starting rebuild")
        building = true
        ino = if process.platform is 'win32' then curr.ino? else curr.ino
        unless ino
          console.error "WARNING: watched file #{file} has disappeared"
          return
        buildBundle()
        building = false
        return

if entryPoints.length == 1 and entryPoints[0] is '-'
  # support reading input from stdin
  stdinput = ''
  process.stdin.on 'data', (data) -> stdinput += data
  process.stdin.on 'end', ->
    entryPoints[0] = (require 'mktemp').createFileSync 'temp-XXXXXXXXX.js'
    fs.writeFileSync entryPoints[0], stdinput
    process.on 'exit', -> fs.unlinkSync entryPoints[0]
    do startBuild
  process.stdin.setEncoding 'utf8'
  do process.stdin.resume
else
  do startBuild
