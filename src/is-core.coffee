resolve = require 'resolve'

CORE_MODULES = require './core-modules'

module.exports = (x) -> (resolve.isCore x) or [].hasOwnProperty.call CORE_MODULES, x
