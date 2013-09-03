fs = require 'fs'
path = require 'path'

{sync: resolve} = require 'resolve'

CORE_MODULES = require './core-modules'
isCore = require './is-core'
canonicalise = require './canonicalise'

resolvePath = ({extensions, aliases, root, cwd, path: givenPath}) ->
  aliases ?= {}
  if isCore givenPath
    return if {}.hasOwnProperty.call aliases, givenPath
    corePath = CORE_MODULES[givenPath]
    unless fs.existsSync corePath
      throw new Error "Core module \"#{givenPath}\" has not yet been ported to the browser"
    givenPath = corePath
  # try regular CommonJS requires
  try resolve givenPath, {extensions, basedir: cwd or root}
  catch e
    # support non-standard root-relative requires
    try resolve (path.join root, givenPath), {extensions}
    catch e then throw new Error "Cannot find module \"#{givenPath}\" in \"#{root}\""

module.exports = ({extensions, aliases, root, cwd, path: givenPath}) ->
  aliases ?= {}
  resolved = resolvePath {extensions, aliases, root, cwd, path: givenPath}
  canonicalName = if isCore givenPath then givenPath else canonicalise root, resolved
  if {}.hasOwnProperty.call aliases, canonicalName
    resolved = aliases[canonicalName] and resolvePath {extensions, aliases, root, path: aliases[canonicalName]}
  {filename: resolved, canonicalName}
