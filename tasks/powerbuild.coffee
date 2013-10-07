_ = require 'lodash'
path = require 'path'
Powerbuild = require '../src'
buildCache = require '../src/build-cache'


NAME = 'powerbuild'
DESC = 'Wraps commonjs projects into single umd function that will run
 anywhere, generating concatenated source maps to debug files individually.'


initialized = false

initSignalHandlers = ->
  if initialized then return
  initialized = true
  process.on 'SIGINT', process.exit
  process.on 'SIGTERM', process.exit


module.exports = (grunt) ->
  grunt.registerMultiTask NAME, DESC, ->
    options = @options()
    if not options.disableDiskCache
      initSignalHandlers()
      cache = buildCache(options.cachePath)
      options.processed = cache.processed
      options.uids = cache.uids
    for f in @files
      opts = _.clone(options)
      opts.entryPoints = grunt.file.expand(f.orig.src)
      opts.output = f.dest
      build = new Powerbuild(opts)
      start = new Date().getTime()
      grunt.log.ok("Build started...")
      {code, map} = build.bundle()
      console.error("Completed in #{new Date().getTime() - start} ms")
      grunt.file.write build.output, code
      grunt.log.ok("Created #{build.output}")
      if build.sourceMap
        grunt.file.write build.sourceMap, map
        grunt.log.ok("Created #{build.sourceMap}")
