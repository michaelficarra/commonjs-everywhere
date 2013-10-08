# Powerbuild

> CommonJS bundler with aliasing, extensibility, and source maps from the minified JS bundle. Forked from commonjs-everywhere adding speed improvements, persistent disk cache for incremental builds, support for reading '// [#@] sourceMappingURL' from input files and bundled grunt task

## Main changes from commonjs-everywhere

  - Escodegen is only used when generating partial source maps, the final
    result is computed manually.
  - For minification esmangle/escodegen is replaced by UglifyJS for two
    reasons:
    * It was breaking in some of my tests
    * It is 10x slower than UglifyJS. For a bundle with 50k lines of code
      UglifyJS took about 4 seconds versus 35 seconds from esmangle/escodegen)
  - Dependency on coffee-script-redux was removed. While its still possible
    to use the 'handlers' option to build compile-to-js languages directly,
    this tool now reads '// @sourceMappingURL' tags from the end of the file
    in order to map correctly to the original files. This means any
    compile-to-js language that produces source maps is supported out-of-box.
  - By default, source maps for npm dependencies are not included.
  - Module paths are replaced by unique identifiers, which leads to a small
    improvement in the resulting size. When the __filename or __dirname
    variables are used, a mapping for that module uid to the filename will
    be used.
  - Multiple entry points can be specified, with the last being exported
    if the 'export' option is used. This can be used to create test bundles.
  - The result is wrapped into [UMD](https://github.com/umdjs/umd).
  - If the 'node' option is unset, it will disable node.js emulation and
    inclusion of core modules. The result can be loaded as a normal node.js
    module.


## Install

    npm install -g powerbuild

## Usage

### CLI

    $ bin/powerbuild --help

      Usage: powerbuild OPT* ENTRY_FILE+ OPT*

      -a, --alias ALIAS:TO      replace requires of file identified by ALIAS with TO
      -h, --handler EXT:MODULE  handle files with extension EXT with module MODULE
      -m, --minify              minify output using uglify.js
      -c, --compress            Compress/optimize code when minifying
                                (automatically enabled by this option). Enabling
                                will break the generated source map.
      -o, --output FILE         output to FILE instead of stdout
      -r, --root DIR            unqualified requires are relative to DIR; default: cwd
      -s, --source-map FILE     output a source map to FILE
      -v, --verbose             verbose output sent to stderr
      -w, --watch               watch input files/dependencies for changes and rebuild bundle
      -x, --export NAME         export the last given entry module as NAME
      --deps                    do not bundle; just list the files that would be bundled
      --help                    display this help message and exit
      --ignore-missing          continue without error when dependency resolution fails
      --inline-source-map       include the source map as a data URI in the generated bundle
      --inline-sources          include source content in generated source maps
      --node                    if needed by any module, emulate a node.js 
                                environment by including globals such as Buffer,
                                process and setImmediate; default: on
      --cache-path              file where to read/write a json-encoded cache that
                                is used for fast, incremental builds.
                                default: '.powerbuild-cache~' in the current
                                directory
      --disable-disk-cache      disables persistence of incremental build cache
                                to disk. Incremental build will only work with the
                                --watch option
      --npm-source-maps         add mappings for npm modules in the resulting
                                source map(significantly increases the build time)
      --version                 display the version number and exit

*Note:* use `-` as an entry file to accept JavaScript over stdin

*Note:* to disable an option, prefix it with `no-`, e.g. `--no-node`

#### Example:

Common usage, a single entry point which will be used to build the entire
dependency graph. Whatever is exported by 'entry-file.js' will go to the
global property 'MyLibrary':

```bash
powerbuild src/entry-file.js --export MyLibrary --source-map my-library.js.map >my-library.js
```

Specify multiple entry points which will be "required" at startup. Only
the last entry point will be exported when used in conjunction with the
'--export' option. This is mostly useful for building test bundles which
can be referenced from a single 'script' tag

```bash
powerbuild test/*.js --source-map tests.js.map -o tests.js
```

Watch every file in the dependency graph and rebuild when a file changes.
Unlike commonjs-everywhere, this tool caches partial builds to disk, so this
is not necessary for incremental builds.

```bash
powerbuild -wo my-library.js -x MyLibrary src/entry-file.js 
```

Use a browser-specific version of `/lib/node-compatible.js` (remember to use
`root`-relative paths for aliasing). An empty alias target is used to delay
errors to runtime when requiring the source module (`fs` in this case). The
'browser' field in package.json will also be used if available when building
bundles with node.js emulation(which is the default). 

```bash
powerbuild -a /lib/node-compatible.js:/lib/browser-compatible.js -a fs: -x MyLibrary lib/entry-file.js
```

### Module Interface

#### `new Powerbuild(options)`
Constructor for an object that can keeps track of build options and is used to
trigger incremental rebuilds.

* `options` is an object that can contain the following properties:
    * `entryPoints` is an array of filenames relative to `process.cwd()` that
      will be used to initialize the bundle. The last item in this array will
      also be used when the 'export' option is specified
    * `root`: Same as cli.
    * `export`: Same as cli.
    * `aliases`: an object whose keys and values are `root`-rooted paths
      (`/src/file.js`), representing values that will replace requires that
      resolve to the associated keys
    * `handlers`: an object whose keys are file extensions (`'.coffee'`) and
      whose values are functions that receives the file contents as arguments
      and returns one of the following:
        - Spidermonkey-format JS AST like the one esprima produces
        - A string of javascript
        - An object with the keys 'code' and 'map' containing strings with
          javascript and sourcemaps respectively.
      A handler for JSON is included by default. If no handler is defined for
      a file extension, it is assumed to be JavaScript. (The default
      coffeescript-redux handler was removed because this tool now reads
      '// @sourceMappingURL' comment tags, so it can be used in conjunction
      with the default coffeescript compiler)
    * `node`: Same as cli. When true(default) the bundling phase will emit
      globals for 'process', 'Buffer' or 'setImmediate' if any of those are
      used by any of the bundled modules. Setting this to false will completely
      disable node.js emulation, excluding core node.js modules(path, util...)
      from the bundle. This may be used to create bundles targeted at node.js.
      (While this will not be a very common case, it can be used for example
      to distribute node.js apps as a single javascript file containing all
      dependencies).
    * `verbose`: Same as cli.
    * `ignoreMissing`: Same as cli.
    * `minify`: Same as cli.
    * `compress`: Same as cli.
    * `output`: Name of the output file. The file will not be written, this
       is used when building the source map.
    * `sourceMap`: Same as cli. This may be true to make the source map have
      the same name as 'output' with '.map' appended.
    * `inlineSourceMap`: Same as cli.
    * `inlineSources`: Same as cli.
    * `npmSourceMaps`: Same as cli. This is disabled by default because
      it greatly increases build efficiency and normally you wont care about
      debugging external modules.


### Grunt task

This package includes a grunt task that takes any of the API or cli options(
with dashes removed and converted to camelCase). For an example see this
package's [test bundle configuration]()

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
powerbuild -o public/javascripts/app.js -x App.Todos -r components components/todos/index.coffee
```

Since the above command specifies `components` as the root directory for
unqualified requires, we are able to require `components/users/model.coffee`
with `require 'users/model'`. The output file will be
`public/javascripts/app.js`.

### Node Module Example

```coffee
opts.root = 'components'
opts.entryPoints = ['index.coffee']
powerbuild = new Powerbuild opts
{code, map} = powerbuild.bundle()
```
