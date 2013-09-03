path = require 'path'

module.exports = (root, file) ->
    file = path.resolve(root, file) # in case if file is a relative path
    "/#{path.relative root, file}".replace /\\/g, '/'
