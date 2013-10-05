{SourceMapConsumer} = require 'source-map'
{traverse} = require 'estraverse'
assert = require 'assert'

module.exports = (ast, srcMap) ->
  map = new SourceMapConsumer srcMap

  traverse ast,
    enter: (node) ->
      if not node.type
        return
      if node.type == 'TryStatement' and not node.guardedHandlers
        node.guardedHandlers = []
      origStart = map.originalPositionFor node.loc.start
      origEnd = map.originalPositionFor node.loc.end
      if origStart.source != origEnd.source
        delete node.loc
        # This is a top-level node like program or a top-level wrapper
        # function, dont care about the source file in these cases
        return
      node.loc =
        start:
          line: origStart.line
          column: origStart.column + 1
        end:
          line: origEnd.line
          column: origEnd.column + 1
        source: origStart.source
