fs = require 'fs'
path = require 'path'
util = require 'util'

_ = require 'lodash'
esprima = require 'esprima'
estraverse = require 'estraverse'
escodegen = require 'escodegen'
escope = require 'escope'
{SourceMapConsumer} = require 'source-map'

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

module.exports = (build, processedCache) ->
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

  if processedCache
    processed = _.clone processedCache
  else
    processed = {}

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
    realCanonicalName = null

    if astOrJs.code?
      try
        # wrap into a function so top-level 'return' statements wont break
        # when parsing
        astOrJs.code = "(function(){#{astOrJs.code}})()"
        ast = esprima.parse astOrJs.code, loc: yes, comment: yes
        # unwrap the function
        ast.body = ast.body[0].expression.callee.body.body
        # adjust the column offsets to ignore the wrapped function
        adjustWrapperLocation = true
        # Fix comments/token position info
        # Also adjust top node end range/column
        ast.loc.end.column -= 4
        lastComment = ast.comments[ast.comments.length - 1]
        if lastComment and match = /[#@] sourceMappingURL=(.+)/.exec(lastComment.value)
          dn = path.dirname(filename)
          mapPath = path.join(dn, match[1])
          m = fs.readFileSync(mapPath, 'utf8')
          consumer = new SourceMapConsumer m
          sources = consumer.sources
          sources[0] = path.resolve(path.join(dn, sources[0]))
          realCanonicalName = path.relative(build.sourceMapRoot, sources[0])
          astOrJs.map = m
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
          if build.ignoreMissing
            return { type: 'Literal', value: null }
          throw e
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
          }
        return

    nodeFeatures = {
      __filename: isImplicit '__filename', scope
      __dirname: isImplicit '__dirname', scope
    }

    baseDir = path.dirname path.resolve __dirname
    if isImplicit 'process', scope
      nodeFeatures.process = globalFeatures.process = true

    if not globalFeatures.setImmediate and (isImplicit 'setImmediate', scope) or nodeFeatures.process
      globalFeatures.setImmediate = true
      resolved = relativeResolve {extensions: build.extensions, aliases, root: build.root, cwd: baseDir, path: 'setimmediate'}
      resolved = _.extend resolved, isCoreModule: true, isNpmModule: true
      nodeFeatures.setImmediate = resolved.filename
      worklist.unshift(resolved)

    if not globalFeatures.Buffer and isImplicit 'Buffer', scope
      globalFeatures.Buffer = true
      resolved = relativeResolve {extensions: build.extensions, aliases, root: build.root, cwd: baseDir, path: 'buffer-browserify'}
      resolved = _.extend resolved, isCoreModule: true, isNpmModule: true
      nodeFeatures.Buffer = resolved.filename
      worklist.unshift(resolved)

    {code, map} = escodegen.generate ast,
      sourceMap: true
      format: escodegen.FORMAT_DEFAULTS
      sourceMapWithCode: true
      sourceMapRoot: build.sourceMapRoot
    map = map.toString()

    # cache linecount for a little more efficiency when calculating offsets
    # later
    lineCount = code.split('\n').length
    processed[filename] = {id, canonicalName, code, map, lineCount, mtime,
      deps, nodeFeatures, isNpmModule, isCoreModule, realCanonicalName}
    if processedCache
      # Cache entries are only updated, never deleted, this enables multiple
      # build configurations to share it
      processedCache[filename] = processed[filename]

  # remove old dependencies
  for own k, {isCoreModule} of processed
    if not (isCoreModule or k of checked)
      delete processed[k]

  return processed
