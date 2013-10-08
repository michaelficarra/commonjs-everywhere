resolve = require 'resolve'

CORE_MODULES = require './core-modules'

module.exports = (x) -> x == 'browser-builtins' or (resolve.isCore x) or [].hasOwnProperty.call CORE_MODULES, x
