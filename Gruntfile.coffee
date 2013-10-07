module.exports = (grunt) ->

  grunt.initConfig
    clean:
      all: ['build']

    powerbuild:
      options:
        sourceMap: true
        node: false
      all:
        files: [
          {src: ['test-setup.coffee', 'test/*.coffee'], dest: 'tests.js'}
          {src: 'src/index.coffee', dest: 'lib/main.js'}
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

  grunt.registerTask('test', ['powerbuild', 'mocha_debug'])
  grunt.registerTask('default', ['test', 'watch'])
