_ = require 'lodash'
acorn = require 'acorn'
coffee = require 'coffee-script'
path = require 'path'
bundle = require './bundle'
traverseDependencies = require './traverse-dependencies'


class Powerbuild
  constructor: (options) ->
    if options.export and options.entryPoints.length != 1
      throw new Error('Can only set the export option with one entry point')

    options.inlineSources ?= false
    options.log or= ->
    options.processed or= {}
    options.uids or= {next: 1, names: []}
    options.checkNpmModules ?= false
    options.npmSourceMaps ?= false
    options.bundleNpmModules ?= true
    options.root or= process.cwd()
    options.node ?= true
    {@output, @export, @entryPoints, @root, @node, @log, @inlineSources,
     @verbose, @ignoreMissing, @sourceMap, @inlineSourceMap,
     @mainModule, @minify, @aliases, @handlers, @processed, @uids,
     @checkNpmModules, @npmSourceMaps} = options

    if @output
      @sourceMapRoot = path.relative(path.dirname(@output), @root)
      if @sourceMap == true
        @sourceMap = "#{@output}.map"

    @handlers =
      '.coffee': (src, canonicalName) ->
        {js, v3SourceMap} = coffee.compile src, sourceMap: true, bare: true
        return {code: js, map: v3SourceMap}
      '.json': (json, canonicalName) ->
        acorn.parse "module.exports = #{json}", locations: yes

    for own ext, handler of options.handlers ? {}
      @handlers[ext] = handler

    @extensions = ['.js', (ext for own ext of @handlers)...]


  bundle: ->
    @traverseDependencies()
    return bundle this


  traverseDependencies: ->
    traverseDependencies this
    if @verbose
      @log "Included modules: #{(Object.keys @processed).sort()}"


  uidFor: (name) ->
    if not {}.hasOwnProperty.call(@uids.names, name)
      uid = @uids.next++
      @uids.names[name] = uid
    return @uids.names[name]


module.exports = Powerbuild
