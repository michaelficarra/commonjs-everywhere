suite 'Bundling (async)', ->

  teardown fs.reset

  test 'basic bundle', (done) ->
    fixtures '/a.js': 'module.exports = 2147483647'
    bundleEval 'a.js', null, (err, o) ->
      throw err if err
      eq 2147483647, o
      do done

  test 'basic dependencies', (done) ->
    fixtures
      '/a.js': 'module.exports = require("./b") + require("./c")'
      '/b.js': 'module.exports = 1'
      '/c.js': 'module.exports = 3'
    bundleEval 'a.js', null, (err, o) ->
      throw err if err
      eq 4, o
      do done

  test 'transitive dependencies', (done) ->
    fixtures
      '/a.js': 'module.exports = 1 + require("./b") + require("./c")'
      '/b.js': 'module.exports = 1 + require("./c") + require("./d")'
      '/c.js': 'module.exports = 1 + require("./d")'
      '/d.js': 'module.exports = 1'
    bundleEval 'a.js', null, (err, o) ->
      throw err if err
      eq 7, o
      do done

  test 'circular dependencies', (done) ->
    fixtures
      '/a.js': '''
        exports.a = 1;
        exports.b = require('./b');
        exports.a = 5;
      '''
      '/b.js': 'module.exports = 2 + require("./a").a'
    bundleEval 'a.js', null, (err, o) ->
      throw err if err
      eq 5, o.a
      eq 3, o.b
      do done

  test 'ignoreMissing option produces null values for missing dependencies', (done) ->
    fixtures '/a.js': 'module.exports = require("./b")'
    async.parallel [
      (cb) =>
        bundleEval 'a.js', null, (err, o) ->
          throw new Error unless err instanceof Error
          do cb
      (cb) =>
        bundleEval 'a.js', {ignoreMissing: yes}, (err, o) ->
          return process.nextTick (-> cb err) if err
          eq null, o
          do cb
    ], done
