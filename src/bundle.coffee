path = require 'path'
{SourceMapConsumer, SourceMapGenerator} = require 'source-map'
{btoa} = require 'Base64'
UglifyJS = require 'uglify-js'
sourceMapToAst = require './sourcemap-to-ast'


PROCESS = """
(function() { var global = this;
  var cwd = '/';
  return {
    title: 'browser',
    version: '#{process.version}',
    browser: true,
    env: {},
    on: function() {},
    argv: [],
    nextTick: setImmediate,
    cwd: function(){ return cwd; },
    chdir: function(dir){ cwd = dir; }
  };
})()
"""

REQUIRE = """
(function() {
  var outer;
  if (typeof require === 'function') {
    outer = require;
  }
  function inner(file, parentModule) {
    if({}.hasOwnProperty.call(inner.cache, file))
      return inner.cache[file];

    var resolved = inner.resolve(file);
    if(!resolved && outer) {
      return inner.cache[file] = outer(file);
    }
    if(!resolved) throw new Error("Failed to resolve module '" + file + "'");

    var module$ = {
      id: file,
      require: inner,
      filename: file,
      exports: {},
      loaded: false,
      parent: parentModule,
      children: []
    };
    if(parentModule) parentModule.children.push(module$);
    var dirname = file.slice(0, file.lastIndexOf('/') + 1);

    inner.cache[file] = module$.exports;
    resolved.call(this, module$, module$.exports, dirname, file);
    module$.loaded = true;
    return inner.cache[file] = module$.exports;
  }

  inner.modules = {};
  inner.cache = {};

  inner.resolve = function(file){
    return {}.hasOwnProperty.call(inner.modules, file) ? inner.modules[file] : void 0;
  };
  inner.define = function(file, fn){ inner.modules[file] = fn; };

  return inner;
})()
"""

wrap = (modules) -> """
  (function(require, undefined) { var global = this;
  #{modules}
  })(#{REQUIRE})
  """

wrapUmd = (exports, commonjs) -> """
  (function(exported) {
    if (typeof exports === 'object') {
      module.exports = exported;
    } else if (typeof define === 'function' && define.amd) {
      define(function() {
        return exported;
      });
    } else {
      #{exports}
    }
  })(#{commonjs});
  """

umdOffset = wrapUmd('', '').split('\n').length


bundle = (build) ->
  result = ''
  resultMap = new SourceMapGenerator
    file: path.basename(build.output)
    sourceRoot: build.sourceMapRoot
  lineOffset = umdOffset
  useProcess = false
  bufferPath = false
  setImmediatePath = false

  for own filename, {id, canonicalName, code, map, lineCount, nodeFeatures} of build.processed
    useProcess = useProcess or nodeFeatures.process
    setImmediatePath = setImmediatePath or nodeFeatures.setImmediate
    bufferPath = bufferPath or nodeFeatures.Buffer
    if typeof id != 'number'
      id = "'#{id}'"
    result += """
      \nrequire.define(#{id}, function(module, exports, __dirname, __filename, undefined){
      #{code}
      });
      """
    lineOffset += 2 # skip linefeed plus the 'require.define' line
    if map
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

  if bufferPath
    {id} = build.processed[bufferPath]
    if typeof id != 'number'
      id = "'#{id}'"
    result += "\nvar Buffer = require(#{id});"

  if setImmediatePath
    {id} = build.processed[setImmediatePath]
    if typeof id != 'number'
      id = "'#{id}'"
    result += "\nrequire(#{id});"

  if useProcess and build.node
    result += "\nvar process = #{PROCESS};"

  for i in [0...build.entryPoints.length]
    entryPoint = build.entryPoints[i]
    {id} = build.processed[entryPoint]
    if typeof id != 'number'
      id = "'#{id}'"
    if i == build.entryPoints.length - 1
      # export the last entry point
      result += "\nreturn require(#{id});"
    else
      result += "\nrequire(#{id});"

  if build.export
    exports = "#{build.export} = exported;"
  else
    exports = ''

  commonjs = wrap(result)

  result = wrapUmd(exports, commonjs)

  return {code: result, map: resultMap.toString()}


module.exports = (build) ->
  {code, map} = bundle build

  if build.minify
    uglifyAst = UglifyJS.parse code
    # Enabling the compressor seems to break the source map, leave commented
    # until a solution is found
    # uglifyAst.figure_out_scope()
    # uglifyAst = uglifyAst.transform UglifyJS.Compressor warnings: false
    uglifyAst.figure_out_scope()
    uglifyAst.compute_char_frequency()
    uglifyAst.mangle_names()
    sm = UglifyJS.SourceMap {
      file: build.output
      root: build.sourceMapRoot
      orig: map
    }
    code = uglifyAst.print_to_string source_map: sm
    map = sm.toString()

  if (build.sourceMap or build.inlineSourceMap) and build.inlineSources
    for own filename, {code: src, canonicalName} of build.processed
      map.setSourceContent canonicalName, src

  sourceMappingUrl =
    if build.output
      path.relative (path.dirname build.output), build.sourceMap
    else build.sourceMap

  if build.inlineSourceMap
    datauri = "data:application/json;charset=utf-8;base64,#{btoa "#{map}"}"
    code = "#{code}\n//# sourceMappingURL=#{datauri}"
  else
    code = "#{code}\n//# sourceMappingURL=#{sourceMappingUrl}"

  return {code, map}
