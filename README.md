# CommonJS Everywhere

CommonJS (node module) browser bundler with source maps from the minified JS bundle to the original source, aliasing for browser overrides, and extensibility for arbitrary compile-to-JS language support.

## Install

    npm install -g commonjs-everywhere

## Usage

### CLI

    $ bin/cjsify --help

      Usage: cjsify OPT* path/to/entry-file.ext OPT*

      -m, --minify           minify output
      -o, --output FILE      output to FILE instead of stdout
      -r, --root DIR         unqualified requires are relative to DIR (default: cwd)
      -s, --source-map FILE  output a source map to FILE
      -v, --verbose          verbose output sent to stderr
      -w, --watch            watch input files/dependencies for changes and rebuild bundle
      -x, --export NAME      export the given entry module as NAME
      --deps                 do not bundle; just list the files that would be bundled
      --help                 display this help message
      --ignore-missing       continue without error when dependency resolution fails
      --node                 include process object; emulate node environment (default: on)

*Note:* use `-` as an entry file to accept JavaScript over stdin

*Note:* to disable an option, prefix it with `no-`, e.g. `--no-node`

#### Example:

Common usage

```bash
cjsify src/entry-file.js --export MyLibrary --source-map-file my-library.js.map >my-library.js
```

Watch entry file, its dependencies, even newly added dependencies. Use `verbose` flag to show that only the files that need to be rebuilt are touched.

```bash
cjsify -wvo my-library.js -x MyLibrary src/entry-file.js
```

### Module Interface

#### `cjsify(entryPoint, root, options)` → Spidermonkey AST
Bundles the given file and its dependencies; returns a Spidermonkey AST representation of the bundle. Run the AST through `escodegen` to generate JS code.

* `entryPoint` is a file relative to `process.cwd()` that will be the initial module marked for inclusion in the bundle as well as the exported module
* `root` is the directory to which unqualified requires are relative; defaults to `process.cwd()`
* `options` is an optional object (defaulting to `{}`) with zero or more of the following properties
    * `export`: a variable name to add to the global scope; assigned the exported object from the `entryPoint` module. Any valid [Left-Hand-Side Expression](http://es5.github.com/#x11.2) may be given instead.
    * `aliases`: an object whose keys and values are `root`-rooted paths (`/src/file.js`), representing values that will replace requires that resolve to the associated keys
    * `handlers`: an object whose keys are file extensions (`'.roy'`) and whose values are functions from the file contents to a Spidermonkey-format JS AST like the one esprima produces. Handles for CoffeeScript and JSON are included by default. If no handler is defined for a file extension, it is assumed to be JavaScript.
    * `node`: a falsey value causes the bundling phase to omit the `process` stub that emulates a node environment
    * `verbose`: log additional operational information to stderr
    * `ignoreMissing`: continue without error when dependency resolution fails

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
cjsify -o public/javascripts/app.js -x App.Todos -r components components/todos/index.coffee
```

Since the above command specifies `components` as the root directory for unqualified requires, we are able to require `components/users/model.coffee` with `require 'users/model'`. The output file will be `public/javascripts/app.js`.

### Node Module Example

```coffee
jsAst = (require 'commonjs-everywhere').cjsify 'src/entry-file.coffee', __dirname,
  export: 'MyLibrary'
  aliases:
    '/src/module-that-only-works-in-node.coffee': '/src/module-that-does-the-same-thing-in-the-browser.coffee'
  handlers:
    '.roy': (roySource, filename) ->
      # the Roy compiler outputs JS code right now, so we parse it with esprima
      (require 'esprima').parse (require 'roy').compile roySource, {filename}

{map, code} = (require 'escodegen').generate jsAst,
  sourceMapRoot: __dirname
  sourceMapWithCode: true
  sourceMap: true
```

### Sample Output

![](http://i.imgur.com/oDcQh8H.png)
