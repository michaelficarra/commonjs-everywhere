acorn = require 'acorn'
path = require 'path'
{SourceMapConsumer, SourceMapGenerator} = require 'source-map'
{btoa} = require 'Base64'
escodegen = require 'escodegen'
UglifyJS = require 'uglify-js'
sourceMapToAst = require './sourcemap-to-ast'

canonicalise = require './canonicalise'

PRELUDE_NODE = """
(function() { var global = this;
  var cwd = '/';
  return {
    title: 'browser',
    version: '#{process.version}',
    browser: true,
    env: {},
    on: function() {},
    argv: [],
    nextTick: global.setImmediate || function(fn){ setTimeout(fn, 0); },
    cwd: function(){ return cwd; },
    chdir: function(dir){ cwd = dir; }
  };
})()
"""

PRELUDE = """
(function() {
  function require(file, parentModule) {
    if({}.hasOwnProperty.call(require.cache, file))
      return require.cache[file];

    var resolved = require.resolve(file);
    if(!resolved) throw new Error('Failed to resolve module ' + file);

    var module$ = {
      id: file,
      require: require,
      filename: file,
      exports: {},
      loaded: false,
      parent: parentModule,
      children: []
    };
    if(parentModule) parentModule.children.push(module$);
    var dirname = file.slice(0, file.lastIndexOf('/') + 1);

    require.cache[file] = module$.exports;
    resolved.call(this, module$, module$.exports, dirname, file);
    module$.loaded = true;
    return require.cache[file] = module$.exports;
  }

  require.modules = {};
  require.cache = {};

  require.resolve = function(file){
    return {}.hasOwnProperty.call(require.modules, file) ? require.modules[file] : void 0;
  };
  require.define = function(file, fn){ require.modules[file] = fn; };

  return require;
})()
"""

wrap = (modules) -> """
  (function(require, undefined) { var global = this;
  #{modules}
  })(#{PRELUDE});
  """

wrapNode = (modules) -> """
  (function(require, process, undefined) { var global = this;
  #{modules}
  })(#{PRELUDE}, #{PRELUDE_NODE});
  """

bundle = (options) ->
  result = ''
  resultMap = new SourceMapGenerator
    file: path.basename(options.outFile)
    sourceRoot: options.sourceMapRoot
  lineOffset = 1 # global wrapper

  for own filename, {id, canonicalName, code, map, lineCount} of options.processed
    if typeof id != 'number'
      id = "'#{id}'"
    result += """
      \nrequire.define(#{id}, function(module, exports, __dirname, __filename){
      #{code}
      });
      """
    lineOffset += 2 # skip linefeed plus the 'require.define' line
    orig = new SourceMapConsumer map
    orig.eachMapping (m) ->
      resultMap.addMapping
        generated:
            line: m.generatedLine + lineOffset
            column: m.generatedColumn
        original:
            line: m.originalLine or m.generatedLine
            column: m.originalColumn or m.generatedColumn
        source: canonicalName
        name: m.name
    lineOffset += lineCount

  if options.export
    {id} = options.processed[options.entryPoints[0]]
    if typeof id != 'number'
      id = "'#{id}'"
    result += "\n#{options.export} = require(#{id});"
  else
    for entryPoint in options.entryPoints
      {id} = options.processed[entryPoint]
      if typeof id != 'number'
        id = "'#{id}'"
      result += "\nrequire(#{id});"

  if options.node
    result = wrapNode(result)
  else
    result = wrap(result)

  return {code: result, map: resultMap.toString()}


module.exports = (options) ->
  {code, map} = bundle options

  if options.minify
    uglifyAst = UglifyJS.parse code
    # Enabling the compressor seems to break the source map, leave commented
    # until a solution is found
    # uglifyAst.figure_out_scope()
    # uglifyAst = uglifyAst.transform UglifyJS.Compressor warnings: false
    uglifyAst.figure_out_scope()
    uglifyAst.compute_char_frequency()
    uglifyAst.mangle_names()
    sm = UglifyJS.SourceMap {
      file: options.output
      root: options.sourceMapRoot
      orig: map
    }
    code = uglifyAst.print_to_string source_map: sm
    map = sm.toString()

  if (options.sourceMap or options.inlineSourceMap) and options.inlineSources
    for own filename, {code: src, canonicalName} of options.processed
      map.setSourceContent canonicalName, src

  if options.inlineSourceMap
    datauri = "data:application/json;charset=utf-8;base64,#{btoa "#{map}"}"
    code = "#{code}\n//# sourceMappingURL=#{datauri}"

  return {code, map}
