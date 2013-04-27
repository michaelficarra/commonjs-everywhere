fs = require 'fs'
path = require 'path'
resolve = require 'resolve'

CORE_MODULES = require './core-modules'
isCore = require './is-core'

module.exports = (extensions, root, givenPath, cwd) ->
  if isCore givenPath
    corePath = CORE_MODULES[givenPath]
    unless fs.existsSync corePath
      throw new Error "Core module \"#{givenPath}\" has not yet been ported to the browser"
    givenPath = corePath
  # try regular CommonJS requires
  try resolve.sync givenPath, {basedir: cwd or root, extensions}
  catch e
    # support non-standard root-relative requires
    try resolve.sync (path.join root, givenPath), {extensions}
    catch e then throw new Error "Cannot find module \"#{givenPath}\" in \"#{root}\""
