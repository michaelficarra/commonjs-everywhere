{SourceMapConsumer} = require 'source-map'
{traverse} = require 'estraverse'
assert = require 'assert'

module.exports = (ast, srcMap) ->
  map = new SourceMapConsumer srcMap

  traverse ast,
    enter: (node) ->
      origStart = map.originalPositionFor node.loc.start
      origEnd = map.originalPositionFor node.loc.end
      assert origStart.source == origEnd.source, 'Invalid source map'
      node.loc =
        start:
          line: origStart.line
          column: origStart.column
        end:
          line: origEnd.line
          column: origEnd.column
        source: origStart.source || node.loc.source
