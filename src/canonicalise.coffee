path = require 'path'

module.exports = (root, file) -> "/#{path.relative root, file}".replace /\\/g, '/'
