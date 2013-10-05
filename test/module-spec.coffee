suite 'Module Spec', ->

  test 'caching', ->
    fixtures
      '/a.js': '''
        ++require('./b').b
        module.exports = require('./b').b
      '''
      '/b.js': 'module.exports = {b: 1}'
    eq 2, bundleEval 'a.js'

  test 'module.parent refers to the parent module', ->
    fixtures
      '/a.js': 'exports.a = 1; exports.b = require("./b")'
      '/b.js': 'module.exports = module.parent.exports.a + 1;'
    obj = bundleEval 'a.js'
    eq 1, obj.a
    eq 2, obj.b

  test 'module.children contains required modules', ->
    fixtures
      '/a.js': 'require("./b"); module.exports = module.children[0].exports'
      '/b.js': 'module.exports = module.filename'
    eq 'b.js', bundleEval 'a.js'
