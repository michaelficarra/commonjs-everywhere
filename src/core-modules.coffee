path = require 'path'
{sync: resolve} = require 'resolve'

CJS_DIR = path.join __dirname, '..'

CORE_MODULES =
  buffer: resolve 'buffer-browserify'
  constants: resolve 'constants-browserify'
  crypto: resolve 'crypto-browserify'
  events: resolve 'events-browserify'
  http: resolve 'http-browserify'
  punycode: resolve('./node_modules/punycode', basedir: CJS_DIR)
  querystring: resolve('./node_modules/querystring', basedir: CJS_DIR)
  vm: resolve 'vm-browserify'
  zlib: resolve 'zlib-browserify'

NODE_CORE_MODULES = [
  '_stream_duplex'
  '_stream_passthrough'
  '_stream_readable'
  '_stream_transform'
  '_stream_writable'
  'assert'
  'console'
  'domain'
  'freelist'
  'path'
  'readline'
  'stream'
  'string_decoder'
  'sys'
  'url'
  'util'
]
for mod in NODE_CORE_MODULES
  CORE_MODULES[mod] = path.join CJS_DIR, 'node', 'lib', "#{mod}.js"

module.exports = CORE_MODULES
