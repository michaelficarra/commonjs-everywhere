suite 'Node Core Libraries', ->

  test 'path', ->
    fixtures '/a.js': 'module.exports = require("path").join("a", "b")'
    eq 'a/b', bundleEvalSync '/a.js', ignoreMissing: yes

  test 'url', ->
    fixtures '/a.js': 'module.exports = require("url").parse("https://github.com")'
    o = bundleEvalSync '/a.js'
    eq 'https:', o.protocol
    eq 'github.com', o.hostname
    eq '/', o.pathname

  test 'querystring', ->
    fixtures '/a.js': 'module.exports = require("querystring").parse("a=b").a'
    eq 'b', bundleEvalSync '/a.js'
