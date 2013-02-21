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

  var dirname = file.slice(0, file.lastIndexOf('/') + 1);
  var process = {
    title: 'browser',
    browser: true,
    env: {},
    argv: [],
    nextTick: function(fn){ setTimeout(fn, 0); },
    cwd: function(){ return dirname; }
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

wrap = (file, statements) ->
  type: 'ExpressionStatement'
  expression:
    type: 'CallExpression'
    callee:
      type: 'MemberExpression'
      computed: false
      object: { type: 'Identifier', name: 'require' }
      property: { type: 'Identifier', name: 'define' }
    arguments: [
      { type: 'Literal', value: file }
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
          body: statements
      }
    ]

exports.relativeResolve = relativeResolve = (root, givenPath, cwd) ->
  resolvedPath =
    try resolve.sync givenPath, basedir: cwd or root, extensions: EXTENSIONS
    catch e then resolve.sync (path.join root, givenPath), extensions: EXTENSIONS
  if fs.existsSync resolvedPath
    "/#{path.relative root, resolvedPath}"
  else
    resolvedPath


exports.build = (entryPoint, exposeAs, projectRoot) ->
  projectRoot ?= path.dirname path.resolve entryPoint

  worklist = [path.resolve entryPoint]
  built = {}
  aliases = {'/lib/make-request.js': '/lib/make-request-browser.js'}

  while worklist.length
    filename = worklist.pop()
    canonicalName = relativeResolve projectRoot, filename
    continue if {}.hasOwnProperty.call built, canonicalName

    if {}.hasOwnProperty.call aliases, canonicalName
      filename = resolve.sync (path.join projectRoot, aliases[canonicalName]), extensions: EXTENSIONS

    if resolve.isCore filename
      filename = path.resolve path.join __dirname, '..', 'core', filename
      unless fs.existsSync filename
        filename = path.resolve path.join __dirname, '..', 'core', 'undefined'

    fileContents = fs.readFileSync filename
    if '.coffee' is path.extname filename
      fileContents = CoffeeScript.cs2js fileContents
    if '.json' is path.extname filename
      fileContents = "module.exports = #{fileContents}"
    ast = esprima.parse fileContents
    built[canonicalName] = ast
    estraverse.replace ast,
      enter: (node, parents) ->
        return unless node.type is 'CallExpression' and node.callee.type is 'Identifier' and node.callee.name is 'require'
        unless node.arguments.length is 1
          badRequireError filename, node, '`require` must be given exactly one argument'
        unless node.arguments[0].type is 'Literal' and typeof node.arguments[0].value is 'string'
          badRequireError filename, node, 'argument of `require` must be a constant string'
        worklist.push resolve.sync node.arguments[0].value, basedir: (path.dirname filename), extensions: EXTENSIONS
        {
          type: 'CallExpression'
          callee: node.callee
          arguments: [
            type: 'Literal'
            value: relativeResolve projectRoot, node.arguments[0].value, path.dirname filename
          ]
        }

  outputProgram = esprima.parse PRELUDE
  for own canonicalName, ast of built
    outputProgram.body.push wrap canonicalName, ast.body

  # expose the entry point
  if exposeAs?
    outputProgram.body.push
      type: 'ExpressionStatement'
      expression:
        type: 'AssignmentExpression'
        operator: '='
        left:
          type: 'MemberExpression'
          computed: true
          object: { type: 'Identifier', name: 'global' }
          property: { type: 'Literal', value: exposeAs }
        right:
          type: 'CallExpression'
          callee: { type: 'Identifier', name: 'require' }
          arguments: [{ type: 'Literal', value: relativeResolve projectRoot, entryPoint }]

  # wrap everything in IIFE for safety, define global var
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
