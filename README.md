# CommonJS Everywhere

Node browser bundler with full source maps from JS/CS to minified JS, aliasing, extensibility.

![](http://i.imgur.com/oDcQh8H.png)

## Install

`npm install commonjs-everywhere`

## Usage

### CLI

```
Usage: cjsify OPT* path/to/entry-file.{js,coffee,json}

-m, --minify            minify output
-o, --output FILE       output to FILE instead of stdout
-r, --root DIR          unqualified requires are relative to DIR (default: cwd)
-x, --export NAME       export the given entry module as NAME
--help                  display this help message
--source-map-file FILE  output a source map to FILE
```

Example:

    cjsify src/entry-file.js --export MyLibrary --source-map-file my-library.js.map >my-library.js

### Module Interface

#### `cjsify(entryPoint, root, options)`
* `entryPoint` is a path relative to `process.cwd()` that will be the initial module marked for inclusion in the bundle as well as the exported module
* `root` is the directory to which unqualified requires are relative; defaults to `process.cwd()`
* `options` is an optional object (defaulting to `{}`) with zero or more of the following properties
    * `export`: a variable name to add to the global scope; assigned the exported object from the `entryPoint` module
    * `aliases`: an object whose keys and values are `root`-rooted paths (`/src/file.js`), representing values that will replace requires that resolve to the associated keys
        * example:
        `{'/src/module-that-only-works-in-node.coffee': '/src/module-that-does-the-same-thing-in-the-browser.coffee'}`
    * `handlers`: an object whose keys are file extensions (`'.roy'`) and whose values are functions from the file contents to a Spidermonkey-format JS AST like the one esprima produces. Handles for CoffeeScript and JSON are included by default. If no handler is defined for a file extension, it is assumed to be JavaScript.
        * example:
        `{'.js': function(jsSource){ return esprima.parse(jsSource); }}`
