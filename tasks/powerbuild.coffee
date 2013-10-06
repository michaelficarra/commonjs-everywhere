_ = require 'lodash'
path = require 'path'
Powerbuild = require '../src'
buildCache = require '../src/build-cache'


NAME = 'powerbuild'
DESC = 'Builds commonjs projects to run anywhere, transpiling to javascript if
necessary, besides generating concatenated source maps.'


cache = buildCache()


module.exports = (grunt) ->
  grunt.registerMultiTask NAME, DESC, ->
    options = @options()
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
