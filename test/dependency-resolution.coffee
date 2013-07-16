suite 'Dependency Resolution', ->

  deps = (entryFile, opts) ->
    entryFile = path.resolve path.join FIXTURES_DIR, entryFile
    for filename in (Object.keys traverseDependencies entryFile, FIXTURES_DIR, opts).sort()
      if filename[...FIXTURES_DIR.length] is FIXTURES_DIR
        "/#{path.relative FIXTURES_DIR, filename}"
      else
        path.relative __dirname, filename

  test 'no dependencies', ->
    fixtures '/a.js': ''
    arrayEq ['/a.js'], deps '/a.js'

  test 'a single dependency', ->
    fixtures
      '/a.js': 'require("./b")'
      '/b.js': ''
    arrayEq ['/a.js', '/b.js'], deps '/a.js'

  test 'more than one dependency', ->
    fixtures
      '/a.js': 'require("./b"); require("./c")'
      '/b.js': ''
      '/c.js': ''
    arrayEq ['/a.js', '/b.js', '/c.js'], deps '/a.js'

  test 'transitive dependencies', ->
    fixtures
      '/a.js': 'require("./b");'
      '/b.js': 'require("./c")'
      '/c.js': ''
    arrayEq ['/a.js', '/b.js', '/c.js'], deps '/a.js'

  test 'circular dependencies', ->
    fixtures
      '/a.js': 'require("./b");'
      '/b.js': 'require("./a")'
    arrayEq ['/a.js', '/b.js'], deps '/a.js'

  test 'core dependencies', ->
    fixtures '/a.js': 'require("punycode")'
    arrayEq ['/a.js', '../node/lib/punycode.js'], deps '/a.js'

  test 'missing dependencies', ->
    fixtures '/a.js': 'require("./b")'
    throws -> deps '/a.js'

  test 'ignoreMissing option ignores missing dependencies', ->
    fixtures '/a.js': 'require("./b")'
    arrayEq ['/a.js'], deps '/a.js', ignoreMissing: yes

  suite 'Aliasing', ->

    test 'basic alias', ->
      fixtures
        '/a.js': 'require("./b")'
        '/b.js': '' # /b.js still needs to exist
        '/c.js': ''
      arrayEq ['/a.js', '/c.js'], deps '/a.js', aliases: {'/b.js': '/c.js'}

    test 'alias to falsey value to omit', ->
      fixtures
        '/a.js': 'require("./b")'
        '/b.js': ''
      arrayEq ['/a.js'], deps '/a.js', aliases: {'/b.js': ''}
      arrayEq ['/a.js'], deps '/a.js', aliases: {'/b.js': null}
      arrayEq ['/a.js'], deps '/a.js', aliases: {'/b.js': false}

    test 'alias a core module', ->
      fixtures '/a.js': 'require("fs")'
      arrayEq ['/a.js', '../node/lib/punycode.js'], deps '/a.js', aliases: {fs: 'punycode'}
      fixtures '/a.js': 'require("path")'
      arrayEq ['/a.js', '../node/lib/path.js', '../node/lib/util.js'], deps '/a.js', aliases: {child_process: null, fs: null}
