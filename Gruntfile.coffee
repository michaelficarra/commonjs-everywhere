coffee = require 'coffee-script'

module.exports = (grunt) ->

  grunt.initConfig
    clean:
      all: ['build']

    coffee:
      options:
        sourceMap: true
      all:
        src: '*.coffee'
        dest: 'lib'
        cwd: 'src'
        flatten: true
        expand: true
        ext: '.js'

    powerbuild:
      options:
        sourceMap: true
        node: false
        handlers:
          '.coffee': (src, canonicalName) ->
            {js, v3SourceMap} = coffee.compile src, sourceMap: true, bare: true
            return {code: js, map: v3SourceMap}

      all:
        files: [
          {src: ['test-setup.coffee', 'test/*.coffee'], dest: 'tests.js'}
        ]

    mocha_debug:
      options:
        ui: 'tdd'
        reporter: 'dot'
        check: ['test-setup.coffee', 'src/*.coffee', 'test/*.coffee']
      all:
        options:
          src: ['tests.js']

    watch:
      options:
        nospawn: true
      all:
        files: [
          'test-setup.coffee'
          'Gruntfile.coffee'
          'tasks/*.coffee'
          'src/*.coffee'
          'test/*.coffee'
        ]
        tasks: [
          'test'
        ]
    

  grunt.loadTasks('tasks')

  grunt.loadNpmTasks('grunt-release')
  grunt.loadNpmTasks('grunt-mocha-debug')
  grunt.loadNpmTasks('grunt-contrib-watch')
  grunt.loadNpmTasks('grunt-contrib-coffee')
  grunt.loadNpmTasks('grunt-newer')

  grunt.registerTask('test', ['newer:coffee', 'powerbuild', 'mocha_debug'])
  grunt.registerTask('default', ['test', 'watch'])
