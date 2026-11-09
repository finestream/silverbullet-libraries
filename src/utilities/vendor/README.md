# Vendored code of the Utilities library

## jsdiff

* `jsdiff-9.0.0.esm.min.js`: [jsdiff](https://github.com/kpdecker/jsdiff) 9.0.0, BSD-3-Clause (`jsdiff-LICENSE`), its ES module entry point bundled into one file and minified:

  ```sh
  curl -sL https://registry.npmjs.org/diff/-/diff-9.0.0.tgz | tar xz
  npx esbuild@0.25.0 package/libesm/index.js --bundle --format=esm --minify --legal-comments=none \
    --outfile=jsdiff-9.0.0.esm.min.js
  ```

* `make vendor-utilities` turns it into `../jsdiff.lua` (`jsdiff.lua.head` plus the file base64-encoded), which the build concatenates like any other Lua fragment. SilverBullet's Lua cannot hold the minified code in a long string (some bracket sequences in it end the string early), so it is carried as base64 and imported from a `data:` URL.

To update jsdiff: replace the `.js` file (and the version in its name, in `jsdiff.lua.head`, in the Makefile and here), then run `make vendor-utilities`.
