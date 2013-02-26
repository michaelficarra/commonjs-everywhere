# CommonJS Everywhere

CommonJS (node module) browser bundler with source maps from the minified JS bundle to the original source, aliasing for browser overrides, and extensibility for arbitrary compile-to-JS language support.

## Install

    npm install -g commonjs-everywhere

## Usage

### CLI

    $ bin/cjsify --help

      Usage: cjsify OPT* path/to/entry-file.{js,coffee,json} OPT*

      -m, --minify            minify output
      -o, --output FILE       output to FILE instead of stdout
      -r, --root DIR          unqualified requires are relative to DIR (default: cwd)
      -x, --export NAME       export the given entry module as NAME
      --help                  display this help message
      --source-map-file FILE  output a source map to FILE

Example:

    cjsify src/entry-file.js --export MyLibrary --source-map-file my-library.js.map >my-library.js

### Module Interface

#### `cjsify(entryPoint, root, options)`
* `entryPoint` is a file relative to `process.cwd()` that will be the initial module marked for inclusion in the bundle as well as the exported module
* `root` is the directory to which unqualified requires are relative; defaults to `process.cwd()`
* `options` is an optional object (defaulting to `{}`) with zero or more of the following properties
    * `export`: a variable name to add to the global scope; assigned the exported object from the `entryPoint` module. This option can be an object with any level of nesting, i.e. `App.Models.User`. Note that, in this example, `App` would have to be previously defined on the global object and its accessed properties would also have to be defined otherwise a type error will be thrown.
    * `aliases`: an object whose keys and values are `root`-rooted paths (`/src/file.js`), representing values that will replace requires that resolve to the associated keys
    * `handlers`: an object whose keys are file extensions (`'.roy'`) and whose values are functions from the file contents to a Spidermonkey-format JS AST like the one esprima produces. Handles for CoffeeScript and JSON are included by default. If no handler is defined for a file extension, it is assumed to be JavaScript.


## Examples

### CLI example

Say we have the following directory tree:

```
* todos/
  * components/
    * users/
      - model.coffee
    * todos/
      - index.coffee
  * public/
    * javascripts/
```
Running the following command will export `index.coffee` and its dependencies as `App.Todos`.

```
jsify -o public/javascripts/app.js -x App.Todos -r components components/todos/index.coffee
```

Since the above command specifies `components` as the root directory for unqualified requires, we are able to require `components/users/model.coffee` with `require 'users/model'`. The output file will be `public/javascripts/app.js`.

### Example with aliases and handlers

```coffee
jsAst = (require 'commonjs-everywhere').cjsify 'src/entry-file.coffee', __dirname,
  export: 'MyLibrary'
  aliases:
    '/src/module-that-only-works-in-node.coffee': '/src/module-that-does-the-same-thing-in-the-browser.coffee'
  handlers:
    '.roy': (roySource) ->
      # the Roy compiler outputs JS code right now, so we parse it with esprima
      (require 'esprima').parse (require 'roy').compile roySource

{map, code} = (require 'escodegen').generate jsAst,
  sourceMapRoot: __dirname
  sourceMapWithCode: true
  sourceMap: true
```

### Sample Output

![](http://i.imgur.com/oDcQh8H.png)
