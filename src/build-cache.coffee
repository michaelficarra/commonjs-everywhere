fs = require 'fs'
path = require 'path'


module.exports = (cachePath = path.join(process.cwd(), '.powerbuild~')) ->
  process.on 'exit', ->
    fs.writeFileSync cachePath, JSON.stringify cache

  process.on 'SIGINT', process.exit
  process.on 'SIGTERM', process.exit

  process.on 'uncaughtException', (e) ->
    # An exception may be thrown due to corrupt cache or incompatibilities
    # between versions, remove it to be safe
    try fs.unlinkSync cachePath
    cache.processed = {}
    throw e

  if fs.existsSync cachePath
    cache = JSON.parse fs.readFileSync cachePath, 'utf8'

  if not cache
    cache =
      processed: {}
      uids: {next: 1, names: []}

  return cache
