suite 'Bundling', ->

  teardown fs.reset

  test 'basic bundle', ->
    fixtures '/a.js': 'module.exports = 2147483647'
    eq 2147483647, bundleEvalSync 'a.js'

  test 'basic dependencies', ->
    fixtures
      '/a.js': 'module.exports = require("./b") + require("./c")'
      '/b.js': 'module.exports = 1'
      '/c.js': 'module.exports = 3'
    eq 4, bundleEvalSync 'a.js'

  test 'transitive dependencies', ->
    fixtures
      '/a.js': 'module.exports = 1 + require("./b") + require("./c")'
      '/b.js': 'module.exports = 1 + require("./c") + require("./d")'
      '/c.js': 'module.exports = 1 + require("./d")'
      '/d.js': 'module.exports = 1'
    eq 7, bundleEvalSync 'a.js'

  test 'circular dependencies', ->
    fixtures
      '/a.js': '''
        exports.a = 1;
        exports.b = require('./b');
        exports.a = 5;
      '''
      '/b.js': 'module.exports = 2 + require("./a").a'
    obj = bundleEvalSync 'a.js'
    eq 5, obj.a
    eq 3, obj.b

  test 'module caching', ->
    fixtures
      '/a.js': '''
        ++require('./b').b
        module.exports = require('./b').b
      '''
      '/b.js': 'module.exports = {b: 1}'
    eq 2, bundleEvalSync 'a.js'

  test 'module.parent refers to the parent module', ->
    fixtures
      '/a.js': 'exports.a = 1; exports.b = require("./b")'
      '/b.js': 'module.exports = module.parent.exports.a + 1;'
    obj = bundleEvalSync 'a.js'
    eq 1, obj.a
    eq 2, obj.b

  test 'module.children contains required modules', ->
    fixtures
      '/a.js': 'require("./b"); module.exports = module.children[0].exports'
      '/b.js': 'module.exports = module.filename'
    eq '/b.js', bundleEvalSync 'a.js'

  test 'ignoreMissing option produces null values for missing dependencies', ->
    fixtures '/a.js': 'module.exports = require("./b")'
    throws -> bundleEvalSync 'a.js'
    eq null, bundleEvalSync 'a.js', ignoreMissing: yes
