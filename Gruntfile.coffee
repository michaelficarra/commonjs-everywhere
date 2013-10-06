module.exports = (grunt) ->

  grunt.initConfig
    clean:
      all: ['build']

    powerbuild:
      options:
        sourceMap: true
        ignoreMissing: true
      all:
        files: [
          {src: ['test-setup.coffee', 'test/*.coffee'], dest: 'bundle.js'}
        ]

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
    

  grunt.loadTasks('tasks')

  grunt.loadNpmTasks('grunt-release')
  grunt.loadNpmTasks('grunt-mocha-debug')
  grunt.loadNpmTasks('grunt-contrib-watch')

  grunt.registerTask('test', ['powerbuild', 'mocha_debug'])
  grunt.registerTask('default', ['test', 'watch'])
