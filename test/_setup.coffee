util = require 'util'
path = require 'path'
async = require 'async'
fs = require 'scopedfs'
escodegen = require 'escodegen'
inspect = (o) -> util.inspect o, no, 2, yes

global[name] = func for name, func of require 'assert'

# See http://wiki.ecmascript.org/doku.php?id=harmony:egal
egal = (a, b) ->
  if a is b
    a isnt 0 or 1/a is 1/b
  else
    a isnt a and b isnt b

# A recursive functional equivalence helper; uses egal for testing equivalence.
arrayEgal = (a, b) ->
  if egal a, b then yes
  else if a instanceof Array and b instanceof Array
    return no unless a.length is b.length
    return no for el, idx in a when not arrayEgal el, b[idx]
    yes

global.eq      = (a, b, msg) -> ok egal(a, b), msg ? "#{inspect a} === #{inspect b}"
global.arrayEq = (a, b, msg) -> ok arrayEgal(a,b), msg ? "#{inspect a} === #{inspect b}"

FIXTURES_DIR = path.join __dirname, 'fixtures'
sfs = fs.scoped FIXTURES_DIR
sfs.reset = ->
  fs.rmrfSync FIXTURES_DIR
  fs.mkdirpSync FIXTURES_DIR
do sfs.reset

global.IN_TESTING_ENVIRONMENT = yes
global[k] = v for own k, v of require '..'
global.FIXTURES_DIR = FIXTURES_DIR
global.path = path
global.async = async
global.escodegen = escodegen
global.fs = sfs
global.fixtures = (opts) ->
  do sfs.reset
  sfs.applySync opts

global.bundleSync = bundleSync = (entryPoint, opts) ->
  escodegen.generate cjsifySync (path.join FIXTURES_DIR, entryPoint), FIXTURES_DIR, opts
global.bundleEvalSync = (entryPoint, opts = {}) ->
  module$ = {}
  opts.export = 'module$.exports'
  eval bundleSync entryPoint, opts
  module$.exports

global.bundle = bundle = (entryPoint, opts, cb) ->
  cjsify (path.join FIXTURES_DIR, entryPoint), FIXTURES_DIR, opts, (err, ast) ->
    return process.nextTick (-> cb err) if err
    process.nextTick -> cb null, escodegen.generate ast
global.bundleEval = (entryPoint, opts = {}, cb = ->) ->
  module$ = {}
  opts.export = 'module$.exports'
  bundle entryPoint, opts, (err, js) ->
    return process.nextTick (-> cb err) if err
    eval js
    process.nextTick -> cb null, module$.exports

extensions = ['.js', '.coffee']
global.resolveSync = (givenPath, cwd = '') ->
  realCwd = path.resolve path.join FIXTURES_DIR, cwd
  relativeResolveSync extensions, FIXTURES_DIR, givenPath, realCwd
global.resolve = (givenPath, cwd = '', cb) ->
  realCwd = path.resolve path.join FIXTURES_DIR, cwd
  relativeResolve extensions, FIXTURES_DIR, givenPath, realCwd, cb
