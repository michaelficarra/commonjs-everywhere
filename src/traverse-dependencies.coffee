fs = require 'fs'
path = require 'path'
util = require 'util'

coffee = require 'coffee-script'
acorn = require 'acorn'
estraverse = require 'estraverse'
escodegen = require 'escodegen'

canonicalise = require './canonicalise'
relativeResolve = require './relative-resolve'
sourceMapToAst = require './sourcemap-to-ast'

badRequireError = (filename, node, msg) ->
  if node.loc? and node.loc?.start?
    filename = "#{filename}:#{node.loc.start.line}:#{node.loc.start.column}"
  throw """
    illegal require: #{msg}
      `#{(require 'escodegen').generate node}`
      in #{filename}
  """

module.exports = (options) ->
  aliases = options.aliases ? {}
  uidFor = options.uidFor
  root = options.root

  handlers =
    '.coffee': (src, canonicalName) ->
      {js, v3SourceMap} = coffee.compile src, sourceMap: true, bare: true
      return {code: js, map: v3SourceMap}
    '.json': (json, canonicalName) ->
      acorn.parse "module.exports = #{json}", locations: yes
  for own ext, handler of options.handlers ? {}
    handlers[ext] = handler
  extensions = ['.js', (ext for own ext of handlers)...]

  worklist = []
  resolvedEntryPoints = []

  for ep in options.entryPoints
    resolved = relativeResolve {extensions, aliases, root, path: ep}
    worklist.push(resolved)
    resolvedEntryPoints.push(resolved.filename)

  options.entryPoints = resolvedEntryPoints

  processed = options.processed or {}
  checked = {}

  while worklist.length
    {filename, canonicalName} = worklist.pop()

    # support aliasing to falsey values to omit files
    continue unless filename

    # filter duplicates
    continue if {}.hasOwnProperty.call checked, filename

    checked[filename] = true
    extname = path.extname filename
    mtime = (fs.statSync filename).mtime.getTime()

    if processed[filename]?.mtime == mtime
      # ignore files that have not changed, but also check its dependencies
      worklist = worklist.concat processed[filename].deps
      continue

    src = (fs.readFileSync filename).toString()

    astOrJs =
      # handle compile-to-JS languages and other non-JS files
      if {}.hasOwnProperty.call handlers, extname
        handlers[extname] src, canonicalName
      else # assume JS
        src

    if typeof astOrJs == 'string'
      astOrJs = {code: astOrJs}

    if astOrJs.code
      try
        ast = acorn.parse astOrJs.code, locations: yes
        ast.loc ?= {}
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
    deps = []
    id = uidFor(canonicalName)

    estraverse.replace ast,
      enter: (node, parents) ->
        if node.loc? then node.loc.source = canonicalName
        if node.type == 'TryStatement' and not node.guardedHandlers
          # escodegen will break when generating from acorn's ast unless
          # we add this
          node.guardedHandlers = []
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
          resolved = relativeResolve {extensions, aliases, root: options.root, cwd, path: node.arguments[0].value}
          worklist.push resolved
          deps.push resolved
        catch e
          if options.ignoreMissing
            return { type: 'Literal', value: null }
          else
            throw e
        # rewrite the require to use the root-relative path or the uid if
        # enabled
        {
          type: 'CallExpression'
          callee: node.callee
          arguments: [{
            type: 'Literal'
            value: uidFor(resolved.canonicalName)
          }, {
            type: 'Identifier'
            name: 'module'
          }]
        }

    {code, map} = escodegen.generate ast,
      sourceMap: yes
      format: escodegen.FORMAT_DEFAULTS
      sourceMapWithCode: yes
      sourceMapRoot: if options.sourceMap? then (path.relative (path.dirname options.sourceMap), options.root) or '.'

    map = map.toString()

    # cache linecount for a little more efficiency when calculating offsets
    # later
    lineCount = code.split('\n').length
    processed[filename] = {id, canonicalName, code, map, lineCount, mtime, deps}

  processed
