suite 'Bundling', ->

  teardown fs.reset

  test 'basic bundle', ->
    fixtures '/a.js': 'module.exports = 2147483647'
    eq 2147483647, bundleEval 'a.js'

  test 'basic dependencies', ->
    fixtures
      '/a.js': 'module.exports = require("./b") + require("./c")'
      '/b.js': 'module.exports = 1'
      '/c.js': 'module.exports = 3'
    eq 4, bundleEval 'a.js'

  test 'transitive dependencies', ->
    fixtures
      '/a.js': 'module.exports = 1 + require("./b") + require("./c")'
      '/b.js': 'module.exports = 1 + require("./c") + require("./d")'
      '/c.js': 'module.exports = 1 + require("./d")'
      '/d.js': 'module.exports = 1'
    eq 7, bundleEval 'a.js'

  test 'circular dependencies', ->
    fixtures
      '/a.js': '''
        exports.a = 1;
        exports.b = require('./b');
        exports.a = 5;
      '''
      '/b.js': 'module.exports = 2 + require("./a").a'
    obj = bundleEval 'a.js'
    eq 5, obj.a
    eq 3, obj.b

  test 'ignoreMissing option produces null values for missing dependencies', ->
    fixtures '/a.js': 'module.exports = require("./b")'
    throws -> bundleEval 'a.js'
    eq null, bundleEval 'a.js', ignoreMissing: yes

  test '#78: fix canonicalisation of paths', ->
    fixtures '/src/main.coffee': 'module.exports = 1'
    doesNotThrow -> bundleEval 'main.coffee', root: 'src'

  test '#91: AMD bundling', ->
    nonce = {}
    define = -> defined.push [].slice.call arguments
    define.amd = true
    fixtures '/a.js': 'module.exports = nonce'

    # no `define` in CommonJS environment
    eq nonce, bundleEval 'a.js', {amd: yes}, {nonce}

    # no `define` in non-CommonJS environment with global export
    global$ = Object.create null
    eq undefined, bundleEval 'a.js', {amd: yes, export: 'moduleName'}, {nonce, global: global$}
    eq nonce, global$.moduleName

    # no `define` in CommonJS environment with global export
    global$ = Object.create null
    global$.module = {exports: global$.exports = Object.create null}
    eq nonce, bundleEval 'a.js', {amd: yes, export: 'moduleName'}, {nonce, global: global$}
    eq undefined, global$.moduleName

    # `define` in CommonJS environment
    defined = []
    eq nonce, bundleEval 'a.js', {amd: yes, export: null}, {nonce, define}
    eq 1, defined.length
    eq 2, defined[0].length
    arrayEq [], defined[0][0]
    eq nonce, defined[0][1]()

    # `define` in non-CommonJS environment with global export
    defined = []
    global$ = Object.create null
    eq undefined, bundleEval 'a.js', {amd: yes, export: 'moduleName'}, {nonce, global: global$, define}
    eq 1, defined.length
    eq 3, defined[0].length
    eq 'moduleName', defined[0][0]
    arrayEq [], defined[0][1]
    eq nonce, defined[0][2]()
    eq nonce, global$.moduleName

    # `define` in CommonJS environment with global export
    defined = []
    eq nonce, bundleEval 'a.js', {amd: yes, export: 'moduleName'}, {nonce, define}
    eq 1, defined.length
    eq 3, defined[0].length
    eq 'moduleName', defined[0][0]
    arrayEq [], defined[0][1]
    eq nonce, defined[0][2]()
