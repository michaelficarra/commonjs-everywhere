path = require 'path'
fs = require 'fs'

resolve = require 'resolve'
esprima = require 'esprima'
estraverse = require 'estraverse'
CoffeeScript = require 'coffee-script-redux'

CORE_DIR = path.join __dirname, '..', 'core'
isCore = do ->
  coreFiles = fs.readdirSync CORE_DIR
  coreFiles = coreFiles.filter (f) -> not (fs.statSync path.join CORE_DIR, f).isDirectory()
  coreFiles = coreFiles.map (f) -> f.replace /\.js$/, ''
  (x) ->
    (resolve.isCore x) or x in coreFiles

PRELUDE = '''
var process = {
  title: 'browser',
  browser: true,
  env: {},
  argv: [],
  nextTick: function(fn){ setTimeout(fn, 0); },
  cwd: function(){ return '/'; },
  chdir: function(){}
};

function require(file){
  if({}.hasOwnProperty.call(require.cache, file))
    return require.cache[file];

  var resolved = require.resolve(file);
  if(!resolved)
    throw new Error('Failed to resolve module ' + file);

  var module$ = {
    id: file,
    require: require,
    filename: file,
    exports: {},
    loaded: false,
    parent: null,
    children: []
  };
  var dirname = file.slice(0, file.lastIndexOf('/') + 1);

  require.cache[file] = module$.exports;
  resolved.call(module$.exports, module$, module$.exports, dirname, file);
  module$.loaded = true;
  return require.cache[file] = module$.exports;
}

require.modules = {};
require.cache = {};

require.resolve = function(file){
  return {}.hasOwnProperty.call(require.modules, file) ? require.modules[file] : void 0;
};
require.define = function(file, fn){ require.modules[file] = fn; };
'''

wrapFile = (name, program) ->
  wrapperProgram = esprima.parse 'require.define(0, function(module, exports, __dirname, __filename){});'
  wrapper = wrapperProgram.body[0]
  wrapper.expression.arguments[0] = { type: 'Literal', value: name }
  wrapper.expression.arguments[1].body.body = program.body
  wrapper

bundle = (processed, entryPoint, options) ->
  program = esprima.parse PRELUDE
  for own canonicalName, ast of processed
    program.body.push wrapFile canonicalName, ast

  requireEntryPoint =
    type: 'CallExpression'
    callee: { type: 'Identifier', name: 'require' }
    arguments: [{ type: 'Literal', value: entryPoint }]

  # require/expose the entry point
  if options.export?
    exportExpression = (esprima.parse options.export).body[0].expression
    lhsExpression =
      if exportExpression.type is 'Identifier'
        type: 'MemberExpression'
        computed: false
        object: { type: 'Identifier', name: 'global' }
        property: { type: 'Identifier', name: exportExpression.name }
      else
        exportExpression
    program.body.push
      type: 'ExpressionStatement'
      expression:
        type: 'AssignmentExpression'
        operator: '='
        left: lhsExpression
        right: requireEntryPoint
  else
    program.body.push
      type: 'ExpressionStatement'
      expression: requireEntryPoint

  # wrap everything in IIFE for safety; define global var
  iife = esprima.parse '(function(global){}).call(this, this);'
  iife.body[0].expression.callee.object.body.body = program.body

  iife


badRequireError = (filename, node, msg) ->
  if node.loc? and node.loc?.start?
    filename = "#{filename}:#{node.loc.start.line}:#{node.loc.start.column}"
  throw """
    illegal require: #{msg}
      `#{(require 'escodegen').generate node}`
      in #{filename}
  """


resolvePath = (extensions, root, givenPath, cwd) ->
  if isCore givenPath
    givenPath = path.resolve path.join CORE_DIR, "#{givenPath}.js"
    unless fs.existsSync givenPath
      givenPath = path.resolve path.join CORE_DIR, 'undefined.js'
  # try regular CommonJS requires
  try resolve.sync givenPath, {basedir: cwd or root, extensions}
  catch e
    # support root-relative requires
    try resolve.sync (path.join root, givenPath), {extensions}
    catch e then throw new Error "Cannot find module \"#{givenPath}\" in \"#{root}\""

exports.relativeResolve = relativeResolve = (extensions, root, givenPath, cwd) ->
  resolvedPath = resolvePath extensions, root, givenPath, cwd
  if fs.existsSync resolvedPath then "/#{path.relative root, resolvedPath}" else resolvedPath


exports.cjsify = (entryPoint, root = process.cwd(), options = {}) ->
  entryPoint = path.resolve entryPoint
  options.aliases ?= {}

  handlers =
    '.coffee': (coffee, canonicalName) ->
      CoffeeScript.compile (CoffeeScript.parse coffee, raw: yes), bare: yes
    '.json': (json, canonicalName) ->
      esprima.parse "module.exports = #{json}", loc: yes, source: canonicalName
  for own ext, handler of options.handlers ? {}
    handlers[ext] = handler
  extensions = ['.js', (ext for own ext of handlers)...]

  worklist = [entryPoint]
  processed = {}

  while worklist.length
    filename = worklist.pop()
    canonicalName = relativeResolve extensions, root, filename

    # filter duplicates
    continue if {}.hasOwnProperty.call processed, canonicalName

    # handle aliases
    if {}.hasOwnProperty.call options.aliases, canonicalName
      filename = resolvePath extensions, root, options.aliases[canonicalName]

    extname = path.extname filename
    fileContents = fs.readFileSync filename

    # handle compile-to-JS languages and other non-JS files
    processed[canonicalName] = ast =
      if {}.hasOwnProperty.call handlers, extname
        handlers[extname](fileContents, canonicalName)
      else # assume JS
        esprima.parse fileContents, loc: yes, source: canonicalName

    source = path.relative root, filename
    # add source file information to the AST root node
    ast.loc ?= {}
    ast.loc.source = source

    estraverse.replace ast,
      enter: (node, parents) ->
        # add source file information to each node with source position information
        if node.loc? then node.loc.source = source
        # ignore anything that's not a `require` call
        return unless node.type is 'CallExpression' and node.callee.type is 'Identifier' and node.callee.name is 'require'
        # illegal requires
        unless node.arguments.length is 1
          badRequireError filename, node, 'require must be given exactly one argument'
        unless node.arguments[0].type is 'Literal' and typeof node.arguments[0].value is 'string'
          badRequireError filename, node, 'argument of require must be a constant string'
        cwd = path.dirname fs.realpathSync filename
        if options.verbose
          console.error "required \"#{node.arguments[0].value}\" from \"#{canonicalName}\""
        # if we are including this file, its requires need to be processed as well
        worklist.push resolvePath extensions, root, node.arguments[0].value, cwd
        # rewrite the require to use the root-relative path
        {
          type: 'CallExpression'
          callee: node.callee
          arguments: [
            type: 'Literal'
            value: relativeResolve extensions, root, node.arguments[0].value, cwd
          ]
        }

  if options.verbose
    console.error "\nIncluded modules:\n  #{(Object.keys processed).sort().join "\n  "}"

  bundle processed, (relativeResolve extensions, root, entryPoint), options
