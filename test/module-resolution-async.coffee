suite 'module resolution', ->

  setup ->
    extensions = ['.js', '.coffee']
    @resolve = resolve = (givenPath, cwd, cb) ->
      realCwd = path.resolve path.join FIXTURES_DIR, cwd
      relativeResolve extensions, FIXTURES_DIR, givenPath, realCwd, cb
    @resolvesTo = (expected, givenPath, cwd) ->
      (cb) ->
        resolve expected, cwd, (err, resolved) ->
          return process.nextTick (-> cb err) if err
          eq expected, resolved
          process.nextTick cb

  teardown fs.reset

  test 'node modules', (done) ->
    fixtures '/node_modules/node-module-name/index.js': ''
    async.parallel [
      @resolvesTo '/node_modules/node-module-name/index.js', 'node-module-name'
      @resolvesTo '/node_modules/node-module-name/index.js', 'node-module-name/index'
    ], done

  test 'relative requires', (done) ->
    async.series [
      (cb) =>
        fixtures '/file.js': ''
        (@resolvesTo '/file.js', './file', null) cb
      (cb) =>
        fixtures '/dir/file.js': ''
        (@resolvesTo '/dir/file.js', './file', 'dir') cb
      (cb) =>
        fixtures
          '/dir/': yes
          '/file.js': ''
        (@resolvesTo '/file.js', '../file', 'dir') cb
    ], done

  test 'CoffeeScript files', (done) ->
    fixtures '/coffee-file.coffee': ''
    (@resolvesTo '/coffee-file.coffee', './coffee-file', null) done

  test '"absolute" paths', (done) ->
    fixtures '/dir/file.js': ''
    async.parallel [
      @resolvesTo '/dir/file.js', 'dir/file'
      @resolvesTo '/dir/file.js', 'dir/file', 'dir'
    ], done

  test 'directories', (done) ->
    fixtures
      '/dir/index.js': ''
      '/dir/dir/index.js': ''
    async.parallel [
      @resolvesTo '/dir/index.js', 'dir'
      @resolvesTo '/dir/index.js', 'dir', 'dir'
      @resolvesTo '/dir/dir/index.js', 'dir/dir'
    ], done

  test 'core module', (done) ->
    async.parallel [
      async.apply @resolve, 'fs', null
      async.apply @resolve, 'fs', 'dir'
    ], done
