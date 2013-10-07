path = require 'path'

suite 'Dependency Resolution', ->

  deps = (entryFile, opts) ->
    entryFile = path.resolve path.join FIXTURES_DIR, entryFile
    opts or= {}
    opts.root = FIXTURES_DIR
    opts.entryPoints = [entryFile]
    powerbuild = new Powerbuild opts
    processed = powerbuild.traverseDependencies()
    rv = []
    for filename in (Object.keys processed).sort()
      if filename[...FIXTURES_DIR.length] is FIXTURES_DIR
        "#{path.relative FIXTURES_DIR, filename}"
      else
        path.relative __dirname, filename

  test 'no dependencies', ->
    fixtures 'a.js': ''
    arrayEq ['a.js'], deps 'a.js'

  test 'a single dependency', ->
    fixtures
      'a.js': 'require("./b")'
      'b.js': ''
    arrayEq ['a.js', 'b.js'], deps 'a.js'

  test 'more than one dependency', ->
    fixtures
      'a.js': 'require("./b"); require("./c")'
      'b.js': ''
      'c.js': ''
    arrayEq ['a.js', 'b.js', 'c.js'], deps 'a.js'

  test 'transitive dependencies', ->
    fixtures
      'a.js': 'require("./b");'
      'b.js': 'require("./c")'
      'c.js': ''
    arrayEq ['a.js', 'b.js', 'c.js'], deps 'a.js'

  test 'circular dependencies', ->
    fixtures
      'a.js': 'require("./b");'
      'b.js': 'require("./a")'
    arrayEq ['a.js', 'b.js'], deps 'a.js'

  test 'core dependencies', ->
    fixtures 'a.js': 'require("freelist")'
    arrayEq ['a.js', '../node/lib/freelist.js'], deps 'a.js'

  suite 'Aliasing', ->

    test 'basic alias', ->
      fixtures
        'a.js': 'require("./b")'
        'b.js': '' # /b.js still needs to exist
        'c.js': ''
      arrayEq ['a.js', 'c.js'], deps 'a.js', aliases: {'b.js': 'c.js'}

    test 'alias to falsey value to omit', ->
      fixtures
        'a.js': 'require("./b")'
        'b.js': ''
      arrayEq ['a.js'], deps 'a.js', aliases: {'b.js': ''}
      arrayEq ['a.js'], deps 'a.js', aliases: {'b.js': null}
      arrayEq ['a.js'], deps 'a.js', aliases: {'b.js': false}

    test 'alias a core module', ->
      fixtures 'a.js': 'require("fs")'
      arrayEq ['a.js', '../node/lib/freelist.js'], deps 'a.js', aliases: {fs: 'freelist'}
      fixtures 'a.js': 'require("path")'
      arrayEq ['a.js', '../node/lib/path.js', '../node/lib/util.js'
        '../node_modules/setimmediate/setImmediate.js'], deps 'a.js', aliases: {child_process: null, fs: null}
