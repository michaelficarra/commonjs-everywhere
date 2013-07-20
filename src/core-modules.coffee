path = require 'path'

CJS_DIR = path.join __dirname, '..'

CORE_MODULES =
  buffer: path.join CJS_DIR, 'node_modules', 'buffer-browserify', 'index.js'
  crypto: path.join CJS_DIR, 'node_modules', 'crypto-browserify', 'index.js'
  events: path.join CJS_DIR, 'node_modules', 'events-browserify', 'events.js'
  http: path.join CJS_DIR, 'node_modules', 'http-browserify', 'index.js'
  punycode: path.join CJS_DIR, 'node_modules', 'punycode', 'punycode.js'
  querystring: path.join CJS_DIR, 'node_modules', 'querystring', 'index.js'
  vm: path.join CJS_DIR, 'node_modules', 'vm-browserify', 'index.js'
  zlib: path.join CJS_DIR, 'node_modules', 'zlib-browserify', 'index.js'

NODE_CORE_MODULES = [
  '_stream_duplex.js'
  '_stream_passthrough.js'
  '_stream_readable.js'
  '_stream_transform.js'
  '_stream_writable.js'
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
