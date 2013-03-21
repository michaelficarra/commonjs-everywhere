suite 'Module Resolution (sync)', ->

  teardown fs.reset

  test 'node modules', ->
    fixtures '/node_modules/node-module-name/index.js': ''
    eq '/node_modules/node-module-name/index.js', resolveSync 'node-module-name'
    eq '/node_modules/node-module-name/index.js', resolveSync 'node-module-name/index'

  test 'relative requires', ->
    fixtures '/file.js': ''
    eq '/file.js', resolveSync './file'

    fixtures '/dir/file.js': ''
    eq '/dir/file.js', resolveSync './file', 'dir'

    fixtures
      '/dir/': yes
      '/file.js': ''
    eq '/file.js', resolveSync '../file', 'dir'

  test 'CoffeeScript files', ->
    fixtures '/coffee-file.coffee': ''
    eq '/coffee-file.coffee', resolveSync './coffee-file'

  test '"absolute" paths', ->
    fixtures '/dir/file.js': ''
    eq '/dir/file.js', resolveSync 'dir/file'
    eq '/dir/file.js', resolveSync 'dir/file', 'dir'

  test 'directories', ->
    fixtures
      '/dir/index.js': ''
      '/dir/dir/index.js': ''
    eq '/dir/index.js', resolveSync 'dir'
    eq '/dir/index.js', resolveSync 'dir', 'dir'
    eq '/dir/dir/index.js', resolveSync 'dir/dir'

  test 'core module', ->
    doesNotThrow => resolveSync 'punycode'
    doesNotThrow => resolveSync 'punycode', 'dir'
