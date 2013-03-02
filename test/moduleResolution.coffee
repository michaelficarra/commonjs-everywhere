suite 'module resolution', ->

  setup ->
    @resolve = (givenPath, cwd) ->
      root = path.join __dirname, 'fixtures'
      relativeResolve ['.js', '.coffee'], root, givenPath, path.resolve path.join root, cwd

  test 'node modules', ->
    eq '/node_modules/node-module-name/index.js', @resolve 'node-module-name'
    eq '/node_modules/node-module-name/index.js', @resolve 'node-module-name/index'

  test 'relative requires', ->
    eq '/file.js', @resolve './file'
    eq '/dir/file.js', @resolve './file', 'dir'
    eq '/file.js', @resolve '../file', 'dir'

  test 'CoffeeScript files', ->
    eq '/coffee-file.coffee', @resolve './coffee-file'

  test '"absolute" paths', ->
    eq '/dir/file.js', @resolve 'dir/file'
    eq '/dir/file.js', @resolve 'dir/file', 'dir'

  test 'directories', ->
    eq '/dir/index.js', @resolve 'dir'
    eq '/dir/index.js', @resolve 'dir', 'dir'
    eq '/dir/dir/index.js', @resolve 'dir/dir'

  test 'core module', ->
    doesNotThrow => @resolve 'fs'
    doesNotThrow => @resolve 'fs', 'dir'
