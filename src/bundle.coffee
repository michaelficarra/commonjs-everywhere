esprima = require 'esprima'
path = require 'path'
{SourceMapConsumer, SourceMapGenerator} = require 'source-map'
{btoa} = require 'Base64'
escodegen = require 'escodegen'
sourceMapToAst = require './sourcemap-to-ast'

canonicalise = require './canonicalise'

PRELUDE_NODE = """
(function(){
  var cwd = '/';
  return {
    title: 'browser',
    version: '#{process.version}',
    browser: true,
    env: {},
    argv: [],
    nextTick: global.setImmediate || function(fn){ setTimeout(fn, 0); },
    cwd: function(){ return cwd; },
    chdir: function(dir){ cwd = dir; }
  };
})()
"""

PRELUDE = """
(function() {
  function require(file, parentModule){
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
    resolved.call(module$.exports, module$, module$.exports, dirname, file);
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
)()
"""

wrap = (modules) -> """
  (function(global, require, undefined) {
  #{modules}
  })(this, #{PRELUDE});
  """

wrapNode = (modules) -> """
  (function(global, require, process, undefined) {
  #{modules}
  })(this, #{PRELUDE}, #{PRELUDE_NODE});
  """

bundle = (options) ->
  result = ''
  resultMap = new SourceMapGenerator
    file: path.basename(options.outFile)
    sourceRoot: path.relative(path.dirname(options.outFile), options.root)
  lineOffset = 1 # global wrapper

  for own filename, {name, code, map, lineCount} of options.processed
    if typeof name != 'number'
      name = "'#{name}'"
    result += """
      \nrequire.define(#{name}, function(module, exports, __dirname, __filename){
      #{code}
      });
      """
    lineOffset += 2# skip linefeed plus the 'require.define' line
    orig = new SourceMapConsumer map
    orig.eachMapping (m) ->
      resultMap.addMapping
        generated:
            line: m.generatedLine + lineOffset
            column: m.generatedColumn
        original:
            line: m.originalLine or m.generatedLine
            column: m.originalColumn or m.generatedColumn
        source: filename

  for entryPoint in options.entryPoints
    name = options.processed[entryPoint].name
    if typeof name != 'number'
      name = "'#{name}'"
    result += "\nrequire(#{name});"

  if options.node
    result = wrapNode(result)
  else
    result = wrap(result)

  return {code: result, map: resultMap}


module.exports = (options) ->
  {code, map} = bundle options

  if options.minify
    esmangle = require 'esmangle'
    ast = esprima.parse bundled, loc: yes
    sourceMapToAst ast, map
    ast = esmangle.mangle (esmangle.optimize ast), destructive: yes
    {code, map} = escodegen.generate ast,
      sourceMap: yes
      format: escodegen.FORMAT_MINIFY
      sourceMapWithCode: yes
      sourceMapRoot: if options.sourceMap? then (path.relative (path.dirname options.sourceMap), options.root) or '.'

  if (options.sourceMap or options.inlineSourceMap) and options.inlineSources
    for own filename, {code} of processed
      map.setSourceContent filename, code

  if options.inlineSourceMap
    datauri = "data:application/json;charset=utf-8;base64,#{btoa "#{map}"}"
    code = "#{code}\n//# sourceMappingURL=#{datauri}"

  return {code, map}
