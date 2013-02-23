# CommonJS Everywhere

Node browser bundler with full source maps from JS/CS to minified JS, aliasing, extensibility.

![](http://i.imgur.com/oDcQh8H.png)

## Install

`npm install commonjs-everywhere`

## Usage

```
Usage: cjsify OPT* path/to/entry-file.{js,coffee}

-m, --minify            minify output
-o, --output FILE       output to FILE instead of stdout
-r, --root DIR          unqualified requires are relative to DIR (default: cwd)
-x, --export NAME       export the given entry module as NAME
--help                  display this help message
--source-map-file FILE  output a source map to FILE
```