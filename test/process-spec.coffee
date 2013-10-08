suite 'Process Spec', ->

  teardown fs.reset

  test 'falsey `node` option disables process emulation', ->
    fixtures '/a.js': 'module.exports = typeof process'
    eq 'object', bundleEval 'a.js'
    eq 'undefined', bundleEval 'a.js', node: no

  test 'process.title is "browser"', ->
    fixtures '/a.js': 'module.exports = process.title'
    eq 'browser', bundleEval 'a.js'

  test 'process.version is the version of node that did the bundling', ->
    fixtures '/a.js': 'module.exports = process.version'
    eq process.version, bundleEval 'a.js'

  test 'process.browser is truthy', ->
    fixtures '/a.js': 'module.exports = process.browser'
    ok bundleEval 'a.js'

  test 'process.cwd defaults to "/"', ->
    fixtures '/a.js': 'module.exports = process.cwd()'
    eq '/', bundleEval 'a.js'

  test 'process.chdir changes process.cwd result', ->
    fixtures '/a.js': 'process.chdir("/dir"); module.exports = process.cwd()'
    eq '/dir', bundleEval 'a.js'

  test 'process.argv is an empty array', ->
    fixtures '/a.js': 'module.exports = process.argv'
    arrayEq [], bundleEval 'a.js'

  test 'process.env is an empty object', ->
    fixtures '/a.js': 'module.exports = Object.keys(process.env)'
    arrayEq [], bundleEval 'a.js'

