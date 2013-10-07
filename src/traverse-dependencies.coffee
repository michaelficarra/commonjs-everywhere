fs = require 'fs'
path = require 'path'
util = require 'util'

_ = require 'lodash'
esprima = require 'esprima'
estraverse = require 'estraverse'
escodegen = require 'escodegen'
escope = require 'escope'

canonicalise = require './canonicalise'
relativeResolve = require './relative-resolve'
sourceMapToAst = require './sourcemap-to-ast'
isCore = require './is-core'


isImplicit = (name, scope) ->
  _.any scope.scopes, (scope) ->
    _.any scope.references, (reference) ->
      reference.identifier.name == name && not reference.resolved


badRequireError = (filename, node, msg) ->
  if node.loc? and node.loc?.start?
    filename = "#{filename}:#{node.loc.start.line}:#{node.loc.start.column}"
  throw """
    illegal require: #{msg}
      `#{(require 'escodegen').generate node}`
      in #{filename}
  """

module.exports = (build) ->
  aliases = build.aliases ? {}
  root = build.root
  globalFeatures = {
    setImmediate: false
    process: false
    Buffer: false
  }

  worklist = []
  resolvedEntryPoints = []

  for ep in build.entryPoints
    resolved = relativeResolve {extensions: build.extensions, aliases, root, path: ep}
    worklist.push(_.assign(resolved, {isNpmModule: false}))
    resolvedEntryPoints.push(resolved.filename)

  build.entryPoints = resolvedEntryPoints

  processed = build.processed
  checked = {}

  while worklist.length
    {filename, canonicalName, isNpmModule, isCoreModule} = worklist.pop()

    # support aliasing to falsey values to omit files
    continue unless filename

    # filter duplicates
    continue if {}.hasOwnProperty.call checked, filename

    checked[filename] = true
    extname = path.extname filename
    mtime = (fs.statSync filename).mtime.getTime()

    if processed[filename]?.mtime == mtime
      # ignore files that have not changed, but also check its dependencies
      for dep in processed[filename].deps
        worklist.push dep
      continue

    src = (fs.readFileSync filename).toString()

    astOrJs =
      # handle compile-to-JS languages and other non-JS files
      if {}.hasOwnProperty.call build.handlers, extname
        build.handlers[extname] src, canonicalName
      else # assume JS
        src

    if typeof astOrJs == 'string'
      astOrJs = {code: astOrJs}

    adjustWrapperLocation = false

    if astOrJs.code?
      try
        # wrap into a function so top-level 'return' statements wont break
        # when parsing
        astOrJs.code = "(function(){#{astOrJs.code}})()"
        ast = esprima.parse astOrJs.code,
          loc: yes, comment: true, range: true, tokens: true
        # unwrap the function
        ast.body = ast.body[0].expression.callee.body.body
        # adjust the range/column offsets to ignore the wrapped function
        adjustWrapperLocation = true
        # Remove the extra tokens
        ast.tokens = ast.tokens.slice(5, ast.tokens.length - 4)
        # Fix comments/token position info
        for t in ast.comments.concat(ast.tokens)
          t.range[0] -= 12
          t.range[1] -= 12
          if t.loc.start.line == 1
            t.loc.start.column -= 12
          if t.loc.end.line == 1
            t.loc.end.column -= 12
        # Also adjust top node end range/column
        ast.range[1] -= 4
        ast.loc.end.column -= 4
        if astOrJs.map
          sourceMapToAst ast, astOrJs.map
      catch e
        if e.lineNumber
          throw new Error "Syntax error in #{filename} at line #{e.lineNumber}, column #{e.column}#{e.message[(e.message.indexOf ':')..]}"
        else
          throw e
    else
      ast = astOrJs

    # add source file information to the AST root node
    ast.loc ?= {}
    scope = escope.analyze ast
    deps = []
    id = build.uidFor(canonicalName)

    estraverse.replace ast,
      enter: (node, parents) ->
        if node.loc?
          node.loc.source = canonicalName
          if node.type != 'Program' and adjustWrapperLocation
            # Adjust the location info to reflect the removed function wrapper 
            if node.loc.start.line == 1 and node.loc.start.column >= 12
              node.loc.start.column -= 12
            if node.loc.end.line == 1 and node.loc.end.column >= 12
              node.loc.end.column -= 12
            node.range[0] -= 12
            node.range[1] -= 12
        # ignore anything that's not a `require` call
        return unless node.type is 'CallExpression' and node.callee.type is 'Identifier' and node.callee.name is 'require'
        # illegal requires
        unless node.arguments.length is 1
          badRequireError filename, node, 'require must be given exactly one argument'
        unless node.arguments[0].type is 'Literal' and typeof node.arguments[0].value is 'string'
          badRequireError filename, node, 'argument of require must be a constant string'
        cwd = path.dirname fs.realpathSync filename
        if build.verbose
          console.error "required \"#{node.arguments[0].value}\" from \"#{canonicalName}\""
        # if we are including this file, its requires need to be processed as
        # well
        try
          moduleName = node.arguments[0].value
          rewriteRequire = false
          if not (isCoreDep = isCoreModule or isCore(moduleName)) or build.node
            rewriteRequire = true
            resolved = relativeResolve {extensions: build.extensions, aliases, root: build.root, cwd, path: moduleName}
            # Only include an external dep if its not a core module or
            # we are emulating a node.js environment
            isNpmDep = isNpmModule or /^[^/.]/.test(moduleName)
            dep = _.assign(resolved, {isNpmModule: isNpmDep, isCoreModule: isCoreDep})
            worklist.push dep
            deps.push dep
        catch e
          rv = undefined
          if build.ignoreMissing
            rv = { type: 'Literal', value: null }
            rv.loc = node.loc
            rv.range = node.range
          return rv
        # rewrite the require to use the root-relative path or the uid if
        # enabled
        if rewriteRequire
          return {
            type: 'CallExpression'
            callee: node.callee
            arguments: [{
              type: 'Literal'
              value: build.uidFor(dep.canonicalName).toString()
            }, {
              type: 'Identifier'
              name: 'module'
            }]
            loc: node.loc
            range: node.range
          }
        return

    nodeFeatures = {
      setImmediate: isImplicit 'setImmediate', scope
      process: isImplicit 'process', scope
      Buffer: isImplicit 'Buffer', scope
      __filename: isImplicit '__filename', scope
      __dirname: isImplicit '__dirname', scope
    }

    baseDir = path.dirname path.resolve __dirname
    if nodeFeatures.process
      globalFeatures.process = true

    if not globalFeatures.setImmediate and nodeFeatures.setImmediate or
        nodeFeatures.process
      globalFeatures.setImmediate = true
      resolved = relativeResolve {extensions: build.extensions, aliases, root: build.root, cwd: baseDir, path: 'setimmediate'}
      resolved = _.extend resolved, isCoreModule: true, isNpmModule: true
      nodeFeatures.setImmediate = resolved.filename
      worklist.unshift(resolved)

    if not globalFeatures.Buffer and nodeFeatures.Buffer
      globalFeatures.Buffer = true
      resolved = relativeResolve {extensions: build.extensions, aliases, root: build.root, cwd: baseDir, path: 'buffer-browserify'}
      resolved = _.extend resolved, isCoreModule: true, isNpmModule: true
      nodeFeatures.Buffer = resolved.filename
      worklist.unshift(resolved)

    {code, map} = escodegen.generate ast,
      comment: true
      sourceMap: true
      format: escodegen.FORMAT_DEFAULTS
      sourceMapWithCode: true
      sourceMapRoot: if build.sourceMap? then (path.relative (path.dirname build.sourceMap), build.root) or '.'
    map = map.toString()

    # cache linecount for a little more efficiency when calculating offsets
    # later
    lineCount = code.split('\n').length
    processed[filename] = {id, canonicalName, code, map, lineCount, mtime,
      deps, nodeFeatures, isNpmModule, isCoreModule}

  # remove old dependencies
  for own k, {isCoreModule} of processed
    if not (isCoreModule or k of checked)
      delete processed[k]

  processed
