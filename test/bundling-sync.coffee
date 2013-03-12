suite 'Bundling', ->

  setup ->
    bundle = (entryPoint, opts) ->
      escodegen.generate cjsifySync (path.join FIXTURES_DIR, entryPoint), FIXTURES_DIR, opts
    @bundleEval = (entryPoint, opts = {}) ->
      module$ = {}
      opts.export = 'module$.exports'
      eval bundle entryPoint, opts
      module$.exports

  teardown fs.reset

  test 'basic bundle', ->
    fixtures '/a.js': 'module.exports = 2147483647'
    eq 2147483647, @bundleEval 'a.js'

  test 'basic dependencies', ->
    fixtures
      '/a.js': 'module.exports = require("./b") + require("./c")'
      '/b.js': 'module.exports = 1'
      '/c.js': 'module.exports = 3'
    eq 4, @bundleEval 'a.js'

  test 'transitive dependencies', ->
    fixtures
      '/a.js': 'module.exports = 1 + require("./b") + require("./c")'
      '/b.js': 'module.exports = 1 + require("./c") + require("./d")'
      '/c.js': 'module.exports = 1 + require("./d")'
      '/d.js': 'module.exports = 1'
    eq 7, @bundleEval 'a.js'

  test 'circular dependencies', ->
    fixtures
      '/a.js': '''
        exports.a = 1;
        exports.b = require('./b');
        exports.a = 5;
      '''
      '/b.js': 'module.exports = 2 + require("./a").a'
    obj = @bundleEval 'a.js'
    eq 5, obj.a
    eq 3, obj.b

  test 'module caching', ->
    fixtures
      '/a.js': '''
        ++require('./b').b
        module.exports = require('./b').b
      '''
      '/b.js': 'module.exports = {b: 1}'
    eq 2, @bundleEval 'a.js'

  test 'module.parent refers to the parent module', ->
    fixtures
      '/a.js': 'exports.a = 1; exports.b = require("./b")'
      '/b.js': 'module.exports = module.parent.exports.a + 1;'
    obj = @bundleEval 'a.js'
    eq 1, obj.a
    eq 2, obj.b

  test 'module.children contains required modules', ->
    fixtures
      '/a.js': 'require("./b"); module.exports = module.children[0].exports'
      '/b.js': 'module.exports = module.filename'
    eq '/b.js', @bundleEval 'a.js'

  test 'ignoreMissing option produces null values for missing dependencies', ->
    fixtures '/a.js': 'module.exports = require("./b")'
    throws -> @bundleEval 'a.js'
    eq null, @bundleEval 'a.js', ignoreMissing: yes
