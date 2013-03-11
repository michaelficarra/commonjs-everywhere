suite 'Dependency Resolution', ->

  setup ->
    @deps = (entryFile, opts) ->
      entryFile = path.resolve path.join FIXTURES_DIR, entryFile
      (Object.keys traverseDependenciesSync entryFile, FIXTURES_DIR, opts).sort()

  test 'no dependencies', ->
    fixtures '/a.js': ''
    arrayEq ['/a.js'], @deps '/a.js'

  test 'a single dependency', ->
    fixtures
      '/a.js': 'require("./b")'
      '/b.js': ''
    arrayEq ['/a.js', '/b.js'], @deps '/a.js'

  test 'more than one dependency', ->
    fixtures
      '/a.js': 'require("./b"); require("./c")'
      '/b.js': ''
      '/c.js': ''
    arrayEq ['/a.js', '/b.js', '/c.js'], @deps '/a.js'

  test 'transitive dependencies', ->
    fixtures
      '/a.js': 'require("./b");'
      '/b.js': 'require("./c")'
      '/c.js': ''
    arrayEq ['/a.js', '/b.js', '/c.js'], @deps '/a.js'
