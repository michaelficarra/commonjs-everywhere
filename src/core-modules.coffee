path = require 'path'

_ = require 'lodash'
browserBuiltins = require 'browser-builtins'

modules = _.clone browserBuiltins
modules.freelist = path.join __dirname, '..', 'core', 'freelist.js'
# delete modules.fs
# delete modules.domain
# delete modules.readline
# delete modules.repl
# delete modules.tls
# delete modules.net
# delete modules.domain
# delete modules.dns
# delete modules.dgram
# delete modules.cluster
# delete modules.child_process


module.exports = modules
