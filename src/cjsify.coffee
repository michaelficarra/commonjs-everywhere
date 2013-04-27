bundle = require './bundle'
traverseDependencies = require './traverse-dependencies'

module.exports = (entryPoint, root = process.cwd(), options = {}) ->
  processed = traverseDependencies entryPoint, root, options
  if options.verbose
    console.error "\nIncluded modules:\n  #{(Object.keys processed).sort().join "\n  "}"
  bundle processed, entryPoint, root, options
