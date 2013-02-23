path = require 'path'
fs = require 'fs'

resolve = require 'resolve'
esprima = require 'esprima'
estraverse = require 'estraverse'
CoffeeScript = require 'coffee-script-redux'

EXTENSIONS = ['.js', '.coffee', '.json']

PRELUDE = '''
function require(file){
  if({}.hasOwnProperty.call(require.cache, file))
    return require.cache[file];

  var resolved = require.resolve(file);
  if(!resolved)
    throw new Error('Failed to resolve module ' + file);

  var process = {
    title: 'browser',
    browser: true,
    env: {},
    argv: [],
    nextTick: function(fn){ setTimeout(fn, 0); },
    cwd: function(){ return '/'; },
    chdir: function(){}
  };
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
  resolved.call(module$.exports, module$, module$.exports, dirname, file, process);
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

wrap = (name, program) ->
  type: 'ExpressionStatement'
  expression:
    type: 'CallExpression'
    callee:
      type: 'MemberExpression'
      computed: false
      object: { type: 'Identifier', name: 'require' }
      property: { type: 'Identifier', name: 'define' }
    arguments: [
      { type: 'Literal', value: name }
      {
        type: 'FunctionExpression'
        id: null
        params: [
          { type: 'Identifier', name: 'module' }
          { type: 'Identifier', name: 'exports' }
          { type: 'Identifier', name: '__dirname' }
          { type: 'Identifier', name: '__filename' }
          { type: 'Identifier', name: 'process' }
        ]
        defaults: []
        body:
          type: 'BlockStatement'
          body: program.body
      }
    ]

resolvePath = (root, givenPath, cwd) ->
  try resolve.sync givenPath, basedir: cwd or root, extensions: EXTENSIONS
  catch e then resolve.sync (path.join root, givenPath), extensions: EXTENSIONS

exports.relativeResolve = relativeResolve = (root, givenPath, cwd) ->
  resolvedPath = resolvePath root, givenPath, cwd
  if fs.existsSync resolvedPath
    "/#{path.relative root, resolvedPath}"
  else
    resolvedPath


exports.cjsify = (entryPoint, root = process.cwd(), options = {}) ->
  options.aliases ?= {}

  handlers =
    '.coffee': (coffee, canonicalName) ->
      CoffeeScript.compile (CoffeeScript.parse coffee, raw: yes), bare: yes
    '.json': (json, canonicalName) ->
      esprima.parse "module.exports = #{json}", loc: yes, source: canonicalName
  for own ext, handler of options.handlers ? {}
    handlers[ext] = handler

  worklist = [path.resolve entryPoint]
  processed = {}

  while worklist.length
    filename = worklist.pop()
    canonicalName = relativeResolve root, filename
    continue if {}.hasOwnProperty.call processed, canonicalName

    if {}.hasOwnProperty.call options.aliases, canonicalName
      filename = resolve.sync "./#{options.aliases[canonicalName]}", basedir: root, extensions: EXTENSIONS

    if resolve.isCore filename
      filename = path.resolve path.join __dirname, '..', 'core', "#{filename}.js"
      unless fs.existsSync filename
        filename = path.resolve path.join __dirname, '..', 'core', 'undefined.js'

    extname = path.extname filename
    fileContents = fs.readFileSync filename

    processed[canonicalName] = ast =
      if {}.hasOwnProperty.call handlers, extname
        handlers[extname](fileContents, canonicalName)
      else # assume JS
        esprima.parse fileContents, loc: yes, source: canonicalName
    ast.loc ?= {}
    ast.loc.source = path.relative root, filename
    estraverse.replace ast,
      enter: (node, parents) ->
        return unless node.type is 'CallExpression' and node.callee.type is 'Identifier' and node.callee.name is 'require'
        unless node.arguments.length is 1
          badRequireError filename, node, '`require` must be given exactly one argument'
        unless node.arguments[0].type is 'Literal' and typeof node.arguments[0].value is 'string'
          badRequireError filename, node, 'argument of `require` must be a constant string'
        worklist.push resolvePath root, node.arguments[0].value, path.dirname filename
        {
          type: 'CallExpression'
          callee: node.callee
          arguments: [
            type: 'Literal'
            value: relativeResolve root, node.arguments[0].value, path.dirname filename
          ]
        }

  outputProgram = esprima.parse PRELUDE
  for own canonicalName, ast of processed
    source = ast.loc.source
    ast = wrap canonicalName, ast
    estraverse.traverse ast, enter: (node) ->
      if node.loc? then node.loc.source = source
      return
    outputProgram.body.push ast

  # expose the entry point
  if options.export?
    outputProgram.body.push
      type: 'ExpressionStatement'
      expression:
        type: 'AssignmentExpression'
        operator: '='
        left:
          type: 'MemberExpression'
          computed: true
          object: { type: 'Identifier', name: 'global' }
          property: { type: 'Literal', value: options.export }
        right:
          type: 'CallExpression'
          callee: { type: 'Identifier', name: 'require' }
          arguments: [{ type: 'Literal', value: relativeResolve root, entryPoint }]

  # wrap everything in IIFE for safety; define global var
  outputProgram.body = [{
    type: 'ExpressionStatement'
    expression:
      type: 'CallExpression'
      callee:
        type: 'FunctionExpression'
        params: [{ type: 'Identifier', name: 'global' }]
        body:
          type: 'BlockStatement'
          body: outputProgram.body
      arguments: [{ type: 'ThisExpression' }]
  }]

  outputProgram
