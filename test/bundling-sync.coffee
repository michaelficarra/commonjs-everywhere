suite 'Bundling (sync)', ->

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

  test 'ignoreMissing option produces null values for missing dependencies', ->
    fixtures '/a.js': 'module.exports = require("./b")'
    throws -> bundleEvalSync 'a.js'
    eq null, bundleEvalSync 'a.js', ignoreMissing: yes
