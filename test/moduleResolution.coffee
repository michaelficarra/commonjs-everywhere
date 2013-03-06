suite 'module resolution', ->

  setup ->
    @resolve = (givenPath, cwd) ->
      root = path.join __dirname, 'fixtures'
      relativeResolve ['.js', '.coffee'], root, givenPath, path.resolve path.join root, cwd

  teardown fs.reset

  test 'node modules', ->
    fixtures '/node_modules/node-module-name/index.js': ''
    eq '/node_modules/node-module-name/index.js', @resolve 'node-module-name'
    eq '/node_modules/node-module-name/index.js', @resolve 'node-module-name/index'

  test 'relative requires', ->
    fixtures '/file.js': ''
    eq '/file.js', @resolve './file'

    fixtures '/dir/file.js': ''
    eq '/dir/file.js', @resolve './file', 'dir'

    fixtures
      '/dir/': yes
      '/file.js': ''
    eq '/file.js', @resolve '../file', 'dir'

  test 'CoffeeScript files', ->
    fixtures '/coffee-file.coffee': ''
    eq '/coffee-file.coffee', @resolve './coffee-file'

  test '"absolute" paths', ->
    fixtures '/dir/file.js': ''
    eq '/dir/file.js', @resolve 'dir/file'
    eq '/dir/file.js', @resolve 'dir/file', 'dir'

  test 'directories', ->
    fixtures
      '/dir/index.js': ''
      '/dir/dir/index.js': ''
    eq '/dir/index.js', @resolve 'dir'
    eq '/dir/index.js', @resolve 'dir', 'dir'
    eq '/dir/dir/index.js', @resolve 'dir/dir'

  test 'core module', ->
    doesNotThrow => @resolve 'fs'
    doesNotThrow => @resolve 'fs', 'dir'
