fs = require 'fs'
path = require 'path'

CoffeeScript = require 'coffee-script-redux'
LiveScript = require 'LiveScript'
esprima = require 'esprima'
estraverse = require 'estraverse'
md5 = require 'MD5'

canonicalise = require './canonicalise'
relativeResolve = require './relative-resolve'

badRequireError = (filename, node, msg) ->
  if node.loc? and node.loc?.start?
    filename = "#{filename}:#{node.loc.start.line}:#{node.loc.start.column}"
  throw """
    illegal require: #{msg}
      `#{(require 'escodegen').generate node}`
      in #{filename}
  """

module.exports = (entryPoint, root = process.cwd(), options = {}) ->
  aliases = options.aliases ? {}

  handlers =
    '.coffee': (coffee, canonicalName) ->
      CoffeeScript.compile (CoffeeScript.parse coffee, raw: yes), bare: yes
    '.json': (json, canonicalName) ->
      esprima.parse "module.exports = #{json}", loc: yes, source: canonicalName
    '.ls': (livescript, canonicalName) ->
      LiveScript.compile livescript

  for own ext, handler of options.handlers ? {}
    handlers[ext] = handler
  extensions = ['.js', (ext for own ext of handlers)...]

  worklist = [relativeResolve {extensions, aliases, root, path: entryPoint}]
  processed = {}

  while worklist.length
    {filename, canonicalName} = worklist.pop()

    # support aliasing to falsey values to omit files
    continue unless filename

    # filter duplicates
    continue if {}.hasOwnProperty.call processed, filename

    extname = path.extname filename
    fileContents = (fs.readFileSync filename).toString()

    # ignore files that have not changed
    if options.cache
      digest = md5 fileContents.toString()
      continue if options.cache[filename] is digest
      options.cache[filename] = digest

    astOrJs =
      # handle compile-to-JS languages and other non-JS files
      if {}.hasOwnProperty.call handlers, extname
        handlers[extname] fileContents, canonicalName
      else # assume JS
        fileContents

    ast =
      if typeof astOrJs is 'string'
        try esprima.parse astOrJs, loc: yes, source: canonicalName
        catch e
          throw new Error "Syntax error in #{filename} at line #{e.lineNumber}, column #{e.column}#{e.message[(e.message.indexOf ':')..]}"
      else
        astOrJs

    processed[filename] = {canonicalName, ast, fileContents}

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
          resolved = relativeResolve {extensions, aliases, root, cwd, path: node.arguments[0].value}
          worklist.push resolved
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
            value: resolved.canonicalName
          }, {
            type: 'Identifier'
            name: 'module'
          }]
        }

  processed
