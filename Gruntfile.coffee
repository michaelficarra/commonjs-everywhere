module.exports = (grunt) ->

  grunt.initConfig
    clean:
      all: ['build']

    powerbuild:
      all:
        'lib': 'src/*.coffee'

    mocha_debug:
      options:
        ui: 'tdd'
        reporter: 'dot'
        check: ['test-setup.coffee', 'src/*.coffee', 'test/*.coffee']
      nodejs:
        options:
          src: ['test-setup.coffee', 'test/*.coffee']

    watch:
      options:
        nospawn: true
      all:
        files: [
          'test-setup.coffee'
          'Gruntfile.coffee'
          'src/*.coffee'
          'test/*.coffee'
        ]
        tasks: [
          'test'
        ]
    

  # grunt.loadTasks('tasks')

  grunt.loadNpmTasks('grunt-release')
  grunt.loadNpmTasks('grunt-mocha-debug')
  grunt.loadNpmTasks('grunt-contrib-watch')

  grunt.registerTask('test', ['mocha_debug'])
  grunt.registerTask('default', ['test', 'watch'])
