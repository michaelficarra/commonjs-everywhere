_ = require 'lodash'
fs = require 'fs'
bundle = require './bundle'
traverseDependencies = require './traverse-dependencies'


class Powerbuild
  constructor: (options) ->
    if options.export and options.entryPoints.length != 1
      throw new Error('Can only set the export option with one entry point')

    options.inlineSources ?= false
    options.log or= ->
    options.root or= process.cwd()
    options.node ?= true
    {@output, @export, @entryPoints, @root, @node, @log, @inlineSources,
     @verbose, @ignoreMissing, @sourceMap, @inlineSourceMap, @moduleUids,
     @mainModule, @minify, @aliases, @handlers} = options

    if @output
      @sourceMapRoot = path.relative(path.dirname(@output), @root)

    if cachePath = options.cachePath
      process.on 'exit', =>
        cache =
          processed: @processed
          uids: @uids
          moduleUids: @moduleUids
        fs.writeFileSync cachePath, JSON.stringify cache

      process.on 'uncaughtException', (e) ->
        # An exception may be thrown due to corrupt cache or incompatibilities
        # between versions, remove it to be safe
        try fs.unlinkSync cachePath
        @processed = {}
        throw e

      if fs.existsSync cachePath
        cache = JSON.parse fs.readFileSync cachePath, 'utf8'
        {@processed, @uids, @moduleUids} = cache

    if not @processed or @moduleUids != options.moduleUids
      # Either the cache doesn't exist or the cache was saved with a different
      # 'moduleUids' value. In either case we must reset it.
      @processed = {}
      @uids = {next: 1, names: {}}


  bundle: ->
    @traverseDependencies()
    bundle this


  traverseDependencies: ->
    traverseDependencies this
    if @verbose
      @log "Included modules: #{(Object.keys @processed).sort()}"


  uidFor: (name) ->
    if not @moduleUids
      return name
    if not {}.hasOwnProperty.call(@uids.names, name)
      uid = @uids.next++
      @uids.names[name] = uid
    @uids.names[name]


module.exports = Powerbuild
