path = require 'path'

module.exports = (root, file) ->
  "/#{path.relative root, path.resolve root, file}".replace /\\/g, '/'
