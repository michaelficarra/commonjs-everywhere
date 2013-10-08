require('source-map-support').install()
escodegen = require 'escodegen'
fs = require 'scopedfs'
path = require 'path'
vm = require 'vm'

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
  else if (Array.isArray a) and Array.isArray b
    return no unless a.length is b.length
    return no for el, idx in a when not arrayEgal el, b[idx]
    yes

inspect = (o) -> (require 'util').inspect o, no, 2, yes
global.eq      = (a, b, msg) -> ok (egal a, b), msg ? "#{inspect a} === #{inspect b}"
global.arrayEq = (a, b, msg) -> ok (arrayEgal a,b), msg ? "#{inspect a} === #{inspect b}"

FIXTURES_DIR = path.join __dirname, 'fixtures'
sfs = fs.scoped FIXTURES_DIR
sfs.reset = ->
  fs.rmrfSync FIXTURES_DIR
  fs.mkdirpSync FIXTURES_DIR
do sfs.reset

global.Powerbuild = require './lib'
global.FIXTURES_DIR = FIXTURES_DIR
global.path = path
global.escodegen = escodegen
global.fs = sfs
global.fixtures = (opts) ->
  do sfs.reset
  sfs.applySync opts

global.bundle = bundle = (entryPoint, opts) ->
  opts.root = path.resolve FIXTURES_DIR, (opts.root ? '')
  opts.entryPoints = [entryPoint]
  powerbuild = new Powerbuild opts
  {code} = powerbuild.bundle()
  return code

global.bundleEval = (entryPoint, opts = {}, env = {}) ->
  global$ = Object.create null
  global$.module$ = module$ = {}
  global$[key] = val for own key, val of env
  opts.export = 'module$.exports'
  code = bundle entryPoint, opts
  vm.runInNewContext code, global$, ''
  module$.exports

extensions = ['.js', '.coffee']
relativeResolve = require './lib/relative-resolve'
global.resolve = (givenPath, cwd = '') ->
  realCwd = path.resolve path.join FIXTURES_DIR, cwd
  resolved = relativeResolve {extensions, root: FIXTURES_DIR, cwd: realCwd, path: givenPath}
  resolved.canonicalName
