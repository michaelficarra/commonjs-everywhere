path = require 'path'
fs = require 'fs'

resolve = require 'resolve'
esprima = require 'esprima'
estraverse = require 'estraverse'
CoffeeScript = require 'coffee-script-redux'
async = require 'async'
# https://github.com/caolan/async/pull/272
async_if = (test, consequent, alternate, cb) ->
  test (err, bool) ->
    return cb err if err?
    if bool then consequent cb else alternate cb
    return
  return

CORE_DIR = path.join __dirname, '..', 'core'
isCore = do ->
  coreFiles = fs.readdirSync CORE_DIR
  coreFiles = coreFiles.filter (f) -> not (fs.statSync path.join CORE_DIR, f).isDirectory()
  coreFiles = coreFiles.map (f) -> f.replace /\.js$/, ''
  (x) ->
    (resolve.isCore x) or x in coreFiles

PRELUDE = """
var process = function(){
  var cwd = '/';
  return {
    title: 'browser',
    version: '#{process.version}',
    browser: true,
    env: {},
    argv: [],
    nextTick: function(fn){ setTimeout(fn, 0); },
    cwd: function(){ return cwd; },
    chdir: function(dir){ cwd = dir; }
  };
}();

function require(file, parentModule){
  if({}.hasOwnProperty.call(require.cache, file))
    return require.cache[file];

  var resolved = require.resolve(file);
  if(!resolved) throw new Error('Failed to resolve module ' + file);

  var module$ = {
    id: file,
    require: require,
    filename: file,
    exports: {},
    loaded: false,
    parent: parentModule,
    children: []
  };
  if(parentModule) parentModule.children.push(module$);
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
"""

wrapFile = (name, program) ->
  wrapperProgram = esprima.parse 'require.define(0, function(module, exports, __dirname, __filename){});'
  wrapper = wrapperProgram.body[0]
  wrapper.expression.arguments[0] = { type: 'Literal', value: name }
  wrapper.expression.arguments[1].body.body = program.body
  wrapper

bundle = (processed, entryPoint, options) ->
  program = esprima.parse PRELUDE
  for own filename, ast of processed
    program.body.push wrapFile ast.loc.source, ast

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


canonicalise = (root, file) -> "/#{path.relative root, file}"


resolvePath = (extensions, root, givenPath, cwd, cb = ->) ->
  test = (cb) -> cb null, isCore givenPath
  consequent = (cb) ->
    # resolve core node modules
    if isCore givenPath
      givenPath = path.resolve path.join CORE_DIR, "#{givenPath}.js"
      fs.exists givenPath, (exists) ->
        if exists then cb null, givenPath
        else throw new Error "Core module \"#{givenPath}\" has not yet been ported to the browser"
  alternate = (cb) -> cb null, givenPath
  async_if test, consequent, alternate, (err, givenPath) ->
    return cb err if err?
    # try regular CommonJS requires
    resolve givenPath, {basedir: cwd or root, extensions}, (err, resolved) ->
      return process.nextTick (-> cb null, resolved) if resolved
      # support root-relative requires
      resolve (path.join root, givenPath), {extensions}, (err, resolved) ->
        return process.nextTick (-> cb null, resolved) if resolved
        process.nextTick -> cb new Error "Cannot find module \"#{givenPath}\" in \"#{root}\""

resolvePathSync = (extensions, root, givenPath, cwd) ->
  if isCore givenPath
    givenPath = path.resolve path.join CORE_DIR, "#{givenPath}.js"
    unless fs.existsSync givenPath
      throw new Error "Core module \"#{givenPath}\" has not yet been ported to the browser"
  # try regular CommonJS requires
  try resolve.sync givenPath, {basedir: cwd or root, extensions}
  catch e
    # support root-relative requires
    try resolve.sync (path.join root, givenPath), {extensions}
    catch e then throw new Error "Cannot find module \"#{givenPath}\" in \"#{root}\""


relativeResolve = (extensions, root, givenPath, cwd, cb = ->) ->
  resolvePath extensions, root, givenPath, cwd, (err, resolved) ->
    return cb err if err?
    cb null, if isCore givenPath then givenPath else canonicalise root, resolved

relativeResolveSync = (extensions, root, givenPath, cwd) ->
  resolved = resolvePathSync extensions, root, givenPath, cwd
  if isCore givenPath then givenPath else canonicalise root, resolved


traverseDependencies = (entryPoint, root = process.cwd(), options = {}, cb = ->) ->
  aliases = options.aliases ? {}

  handlers =
    '.coffee': (coffee, canonicalName) ->
      CoffeeScript.compile (CoffeeScript.parse coffee, raw: yes), bare: yes
    '.json': (json, canonicalName) ->
      esprima.parse "module.exports = #{json}", loc: yes, source: canonicalName
  for own ext, handler of options.handlers ? {}
    handlers[ext] = handler
  extensions = ['.js', (ext for own ext of handlers)...]

  processed = {}
  q = null

  work = ({filename, canonicalName}, next) ->
    # filter duplicates
    return do next if {}.hasOwnProperty.call processed, filename

    # handle aliases
    test = (cb) -> cb null, {}.hasOwnProperty.call aliases, canonicalName
    consequent = (cb) -> resolvePath extensions, root, aliases[canonicalName], cb
    alternate = (cb) -> cb null, filename
    async_if test, consequent, alternate, (err, filename) ->
      return next err if err?

      extname = path.extname filename
      fs.readFile filename, (err, fileContents) ->
        return next err if err?

        # handle compile-to-JS languages and other non-JS files
        processed[filename] = ast =
          if {}.hasOwnProperty.call handlers, extname
            handlers[extname](fileContents, canonicalName)
          else # assume JS
            esprima.parse fileContents, loc: yes, source: canonicalName

        # add source file information to the AST root node
        ast.loc ?= {}

        try
          estraverse.replace ast,
            enter: (node, parents) ->
              # add source file information to each node with source position information
              if node.loc? then node.loc.source = canonicalName
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
              try
                targetCanonicalName = relativeResolveSync extensions, root, node.arguments[0].value, cwd
                q.push
                  filename: resolvePathSync extensions, root, node.arguments[0].value, cwd
                  canonicalName: targetCanonicalName
              catch e
                if options.ignoreMissing
                  return { type: 'Literal', value: null }
                else
                  throw e
              # rewrite the require to use the root-relative path
              {
                type: 'CallExpression'
                callee: node.callee
                arguments: [{
                  type: 'Literal'
                  value: targetCanonicalName
                }, {
                  type: 'Identifier'
                  name: 'module'
                }]
              }
        catch e
          return next e

        do next

  process.nextTick ->
    q = async.queue work, 9e9
    q.drain = (err) -> cb err, processed
    q.push
      filename: path.resolve entryPoint
      canonicalName: canonicalise root, entryPoint
  return


traverseDependenciesSync = (entryPoint, root = process.cwd(), options = {}) ->
  aliases = options.aliases ? {}

  handlers =
    '.coffee': (coffee, canonicalName) ->
      CoffeeScript.compile (CoffeeScript.parse coffee, raw: yes), bare: yes
    '.json': (json, canonicalName) ->
      esprima.parse "module.exports = #{json}", loc: yes, source: canonicalName
  for own ext, handler of options.handlers ? {}
    handlers[ext] = handler
  extensions = ['.js', (ext for own ext of handlers)...]

  worklist = [
    filename: path.resolve entryPoint
    canonicalName: canonicalise root, entryPoint
  ]
  processed = {}

  while worklist.length
    {filename, canonicalName} = worklist.pop()

    # filter duplicates
    continue if {}.hasOwnProperty.call processed, filename

    # handle aliases
    if {}.hasOwnProperty.call aliases, canonicalName
      filename = resolvePathSync extensions, root, aliases[canonicalName]

    extname = path.extname filename
    fileContents = fs.readFileSync filename

    # handle compile-to-JS languages and other non-JS files
    processed[filename] = ast =
      if {}.hasOwnProperty.call handlers, extname
        handlers[extname](fileContents, canonicalName)
      else # assume JS
        esprima.parse fileContents, loc: yes, source: canonicalName

    # add source file information to the AST root node
    ast.loc ?= {}

    estraverse.replace ast,
      enter: (node, parents) ->
        # add source file information to each node with source position information
        if node.loc? then node.loc.source = canonicalName
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
        try
          targetCanonicalName = relativeResolveSync extensions, root, node.arguments[0].value, cwd
          worklist.push
            filename: resolvePathSync extensions, root, node.arguments[0].value, cwd
            canonicalName: targetCanonicalName
        catch e
          if options.ignoreMissing
            return { type: 'Literal', value: null }
          else
            throw e
        # rewrite the require to use the root-relative path
        {
          type: 'CallExpression'
          callee: node.callee
          arguments: [{
            type: 'Literal'
            value: targetCanonicalName
          }, {
            type: 'Identifier'
            name: 'module'
          }]
        }

  processed


cjsify = (entryPoint, root = process.cwd(), options = {}, cb = ->) ->
  traverseDependencies entryPoint, root, options, (err, processed) ->
    return process.nextTick (-> cb err) if err
    if options.verbose
      console.error "\nIncluded modules:\n  #{(Object.keys processed).sort().join "\n  "}"
    cb null, bundle processed, (canonicalise root, entryPoint), options

cjsifySync = (entryPoint, root = process.cwd(), options = {}) ->
  processed = traverseDependenciesSync entryPoint, root, options
  if options.verbose
    console.error "\nIncluded modules:\n  #{(Object.keys processed).sort().join "\n  "}"
  bundle processed, (canonicalise root, entryPoint), options


exports.bundle = bundle
exports.cjsify = cjsify
exports.cjsifySync = cjsifySync
exports.traverseDependencies = traverseDependencies
exports.traverseDependenciesSync = traverseDependenciesSync

if IN_TESTING_ENVIRONMENT?
  exports.badRequireError = badRequireError
  exports.canonicalise = canonicalise
  exports.isCore = isCore
  exports.relativeResolve = relativeResolve
  exports.relativeResolveSync = relativeResolveSync
  exports.resolvePath = resolvePath
  exports.resolvePathSync = resolvePathSync
  exports.wrapFile = wrapFile
