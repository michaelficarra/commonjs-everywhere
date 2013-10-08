_ = require 'lodash'
esprima = require 'esprima'
path = require 'path'
bundle = require './bundle'
traverseDependencies = require './traverse-dependencies'


class Powerbuild
  constructor: (options) ->
    if options.export and options.entryPoints.length != 1
      throw new Error('Can only set the export option with one entry point')

    options.inlineSources ?= false
    if options.compress
      options.minify = true
    options.uids or= {next: 1, names: {}}
    options.npmSourceMaps ?= false
    options.root or= process.cwd()
    options.node ?= true
    {@output, @export, @entryPoints, @root, @node, @inlineSources,
     @verbose, @ignoreMissing, @sourceMap, @inlineSourceMap,
     @mainModule, @minify, @aliases, @handlers, @processed, @uids,
     @npmSourceMaps, @compress, @debug} = options

    @sourceMapRoot = if @sourceMap? then (path.relative (path.dirname @sourceMap), @root) or '.'

    if @output
      @sourceMapRoot = path.relative(path.dirname(@output), @root)
      if @sourceMap == true
        @sourceMap = "#{@output}.map"

    @handlers =
      '.json': (json, canonicalName) ->
        esprima.parse "module.exports = #{json}", loc: yes

    for own ext, handler of options.handlers ? {}
      @handlers[ext] = handler

    @extensions = ['.js', (ext for own ext of @handlers)...]


  bundle: ->
    return bundle this, @traverseDependencies()


  traverseDependencies: ->
    processed = traverseDependencies this, @processed
    if @verbose
      console.error "Included modules: #{(Object.keys processed).sort()}"
    return processed


  uidFor: (name) ->
    if @debug
      return name
    if not {}.hasOwnProperty.call(@uids.names, name)
      uid = @uids.next++
      @uids.names[name] = uid
    return @uids.names[name]


module.exports = Powerbuild
