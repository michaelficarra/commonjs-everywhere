bundle = require './bundle'
traverseDependencies = require './traverse-dependencies'

exports.bundle = bundle
exports.traverseDependencies = traverseDependencies
exports.cjsify = (options = {}) ->
  if options.export and options.entryPoints.length != 1
    throw new Error('Can only set the export option with one entry point')
  options.processed or= {}
  if options.output
    options.sourceMapRoot =
      path.relative(path.dirname(options.output), options.root)
  options.alias ?= []
  options.aliases = {}
  for aliasPair in options.alias
    match = aliasPair.match /([^:]+):(.*)/ ? []
    if match? then options.aliases[match[1]] = match[2]
    else
      console.error "invalid alias: #{aliasPair}"
      process.exit 1
  delete options.alias
  options.handler ?= []
  options.handlers = {}
  for handlerPair in options.handler
    match = handlerPair.match /([^:]+):(.*)/ ? []
    if match? then do (ext = ".#{match[1]}", mod = match[2]) ->
      options.handlers[ext] = require mod
    else
      console.error "invalid handler: #{handlerPair}"
      process.exit 1
  delete options.handler
  options.inlineSources ?= false
  options.cachePath ?= '.powerbuild-cache~'
  options.log or= ->
  options.root or= process.cwd()
  options.uidFor or= (name) -> name
  options.node ?= true
  options.processed = {}
  traverseDependencies options
  if options.verbose
    options.log "\nIncluded modules:\n  #{(Object.keys options.processed).sort().join "\n  "}"
  bundle options
