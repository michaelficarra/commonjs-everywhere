suite 'Process', ->

  setup ->
    bundle = (entryPoint, opts) ->
      escodegen.generate cjsifySync (path.join FIXTURES_DIR, entryPoint), FIXTURES_DIR, opts
    @bundleEval = (entryPoint, opts = {}) ->
      module$ = {}
      opts.export = 'module$.exports'
      eval bundle entryPoint, opts
      module$.exports

  teardown fs.reset

  test 'process.title is "browser"', ->
    fixtures '/a.js': 'module.exports = process.title'
    eq 'browser', @bundleEval 'a.js'

  test 'process.browser is truthy', ->
    fixtures '/a.js': 'module.exports = process.browser'
    ok @bundleEval 'a.js'
