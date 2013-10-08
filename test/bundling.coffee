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

  test 'ignoreMissing option throws resolve exception at runtime', ->
    fixtures '/a.js': 'module.exports = require("./b")'
    throws((-> bundleEval('a.js')), /Cannot find module/)
    eq bundleEval('a.js', ignoreMissing: true), null

  test '#78: fix canonicalisation of paths', ->
    fixtures '/src/main.coffee': 'module.exports = 1'
    doesNotThrow -> bundleEval 'main.coffee', root: 'src'
