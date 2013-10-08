fs = require 'fs'
path = require 'path'

initialized = false

initSignalHandlers = ->
  if initialized then return
  initialized = true
  process.on 'SIGINT', process.exit
  process.on 'SIGTERM', process.exit
  process.on 'uncaughtException', (e) ->
    # to be safe, remove all cache files
    for own k of caches
      if fs.existsSync(k)
        fs.unlinkSync(k)
    throw e

caches = {}

module.exports = (cachePath = path.join(process.cwd(), '.powerbuild~')) ->
  if {}.hasOwnProperty.call caches, cachePath
    return caches[cachePath]

  initSignalHandlers()

  process.on 'exit', ->
    fs.writeFileSync cachePath, JSON.stringify caches[cachePath]

  process.on 'uncaughtException', (e) ->
    # An exception may be thrown due to corrupt cache or incompatibilities
    # between versions, remove it to be safe
    try fs.unlinkSync cachePath
    caches[cachePath].processed = {}
    throw e

  if fs.existsSync cachePath
    caches[cachePath] = JSON.parse fs.readFileSync cachePath, 'utf8'

  if not caches[cachePath]
    caches[cachePath] =
      processed: {}
      uids: {next: 1, names: []}

  return caches[cachePath]
