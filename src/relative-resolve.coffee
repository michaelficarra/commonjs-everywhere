canonicalise = require './canonicalise'
isCore = require './is-core'
resolvePath = require './resolve-path'

module.exports = (extensions, root, givenPath, cwd) ->
  resolved = resolvePath extensions, root, givenPath, cwd
  if isCore givenPath then givenPath else canonicalise root, resolved
