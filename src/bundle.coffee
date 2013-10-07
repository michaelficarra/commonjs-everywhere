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

commonjs = (filenameMap) -> """
  (function() {
    var files = #{JSON.stringify(filenameMap)};
    var outer;
    if (typeof require === 'function') {
      outer = require;
    }
    function inner(id, parentModule) {
      if({}.hasOwnProperty.call(inner.cache, id))
        return inner.cache[id];

      var resolved = inner.resolve(id);
      if(!resolved && outer) {
        return inner.cache[id] = outer(id);
      }
      if(!resolved) throw new Error("Failed to resolve module '" + id + "'");

      var dirname;
      var filename = files[id] || '';
      if (filename)
        dirname = filename.slice(0, filename.lastIndexOf('/') + 1);
      else
        dirname = '';
      var module$ = {
        id: id,
        require: inner,
        exports: {},
        loaded: false,
        parent: parentModule,
        children: []
      };
      if(parentModule) parentModule.children.push(module$);

      inner.cache[id] = module$.exports;
      resolved.call(this, module$, module$.exports, dirname, filename);
      module$.loaded = true;
      return inner.cache[id] = module$.exports;
    }

    inner.modules = {};
    inner.cache = {};

    inner.resolve = function(id){
      return {}.hasOwnProperty.call(inner.modules, id) ? inner.modules[id] : void 0;
    };
    inner.define = function(id, fn){ inner.modules[id] = fn; };

    return inner;
  })()
  """

wrap = (modules, commonjs) -> """
  (function(require, undefined) { var global = this;
  #{modules}
  })(#{commonjs})
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

  files = {}

  for own filename, {id, canonicalName, code, map, lineCount, isNpmModule, nodeFeatures} of build.processed
    if nodeFeatures.__filename or nodeFeatures.__dirname
      files[id] = canonicalName
    useProcess = useProcess or nodeFeatures.process
    setImmediatePath = setImmediatePath or nodeFeatures.setImmediate
    bufferPath = bufferPath or nodeFeatures.Buffer
    result += """
      \nrequire.define('#{id}', function(module, exports, __dirname, __filename, undefined){
      #{code}
      });
      """
    lineOffset += 2 # skip linefeed plus the 'require.define' line
    if build.npmSourceMaps or not isNpmModule
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
    result += "\nvar Buffer = require('#{id}');"

  if setImmediatePath
    {id} = build.processed[setImmediatePath]
    result += "\nrequire('#{id}');"

  if useProcess and build.node
    result += "\nvar process = #{PROCESS};"

  for i in [0...build.entryPoints.length]
    entryPoint = build.entryPoints[i]
    {id} = build.processed[entryPoint]
    if i == build.entryPoints.length - 1
      # export the last entry point
      result += "\nreturn require('#{id}');"
    else
      result += "\nrequire('#{id}');"

  if build.export
    exports = "#{build.export} = exported;"
  else
    exports = ''

  req = commonjs(files)

  cjs = wrap(result, req)

  result = wrapUmd(exports, cjs)

  return {code: result, map: resultMap.toString()}


module.exports = (build) ->
  {code, map} = bundle build

  if build.minify
    uglifyAst = UglifyJS.parse code
    if build.compress
      uglifyAst.figure_out_scope()
      uglifyAst = uglifyAst.transform UglifyJS.Compressor warnings: false
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
