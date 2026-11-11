# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of [SilverBullet](https://silverbullet.md) libraries written in Space-Lua. A "library" here is **not** a plug/JS bundle: it is a single markdown page that a user installs into their SilverBullet space via the Library Manager, containing documentation plus one ` ```space-lua ` code block (and, for kanboard, a ` ```space-style ` block in its docs page). Four libraries so far: `kanboard` (SilverBullet ↔ Kanboard task sync), `imagegallery` (paginated thumbnail grids of the images in a space), `itam` (the page `ITAM`, IT asset management: tag schemas, views and page templates for documenting a set-up as pages) and `utilities` (the page `Utilities`: a tag cloud, a space health table and change proposals).

Users install from `REPO.md` (the repository index, consumed as a raw GitHub URL), which lists one `#meta/library/remote` block per library pointing at `releases/<Page>.md`.

## Build / test / release

Everything goes through the Makefile (`make help` lists targets). Env overrides come from `.env` (gitignored — copy `.env.example`).

```sh
make            # = make help
make build      # build every library: src/<lib>/* -> test/build/<Page>.md
make <lib>      # build one library, e.g. make imagegallery
make testspace  # build + assemble test/test/ space and generate its CONFIG.md from .env
make test       # build + testspace + run SilverBullet in Docker on $SB_HOST_PORT, open browser
make clean      # kill the container, rm -rf test/build test/test
make versions   # source vs released version of every library
make bump-fix-<lib> / bump-feature-<lib>   # edit src/<lib>/RELEASE_PATCH / RELEASE_MINOR
make release-<lib>  # publish one library
make release        # publish every library whose version has been bumped
```

There is **no automated test suite and no linter** — "testing" means `make test` and exercising the commands by hand inside the SilverBullet UI. Because a library only exists as generated markdown, always `make build` (or `make test`) after editing `src/` and never edit the generated artifacts.

Two things do give a real feedback loop, though:

- **`luac -p src/<lib>/*.lua`** catches syntax errors without a browser (Space Lua is a superset-ish dialect, so this is a smoke test, not a guarantee).
- **The Runtime API.** SilverBullet ≥2.9 ships a headless Chrome client and the test container reports `Runtime API enabled` on startup, so the space's *actual* Lua environment can be driven over HTTP:

  ```sh
  curl -d 'ImageGallery.listImages("Images")' http://localhost:3000/.runtime/lua
  curl -d 'local w = imageGallery("Images", 3, 2, 200, 150)
  return w.html.outerHTML' http://localhost:3000/.runtime/lua_script
  ```

  `POST /.runtime/lua` evaluates one expression, `/.runtime/lua_script` a whole script with `return`; both answer `{"result": ...}` or `{"error": ...}`. This reaches `dom`, `widget`, `space.*`, `editor.navigate`, and even `element.click()`, so widgets and their event handlers can be asserted on without a browser.

  Three things to know before trusting it:

  - **The client caches the space-lua environment.** After `make testspace`, `docker restart silverbullet-test` and wait ~20s, then confirm the new code is actually live (assert on something that changed) before concluding anything. Never `js.window.location.reload()` — it unregisters the runtime hook and every later call fails with `sbRuntime.evalLuaScript is not a function` until the container is restarted.
  - **Asserting on a returned widget table proves nothing about the page.** A widget can be perfectly well-formed and still not render. Navigate to a page and query the real DOM (`js.window.document.querySelectorAll(...)`), and check `img.complete` / `img.naturalWidth` to prove images actually loaded. CodeMirror virtualizes the viewport, so only widgets in view exist in the DOM — scroll `.cm-scroller` to reach the rest, and don't read "0 found" as "broken".
  - **The cursor hides a widget.** Right after `editor.navigate` the cursor sits at position 0, so a directive on the first line renders as its own source instead of as a widget. Put text above the directive in test pages.

**Libraries are versioned and released independently.** Each keeps its own `RELEASE_MAJOR`/`RELEASE_MINOR`/`RELEASE_PATCH` in `src/<lib>/`, and `make release-<lib>` writes `releases/<Page>.md` + `releases/<Page>.VERSION` and tags `<lib>-vX.Y.Z`. A library whose version is already published is skipped with a message (so `make release` republishes nothing), which means the bump has to come first.

### Adding a library

Create `src/<lib>/` with `frontmatter.md`, a docs page, one or more `.lua` files, and the three `RELEASE_*` files (start at `0.1.0`); then in the Makefile add `<lib>` to `LIBRARIES` and define `<lib>_PAGE`, `<lib>_DOCS` and `<lib>_LUA` (the `_DOCS`/`_LUA` order *is* the concatenation order). A library that ships extra pages or files (page templates, plugs) lists them in `<lib>_FILES` (paths relative to `src/<lib>/`, no spaces, since make splits on them) *and* under `files:` in its frontmatter: the build copies them next to the page, and SilverBullet installs them next to the library page in the space (`Library/Finestream/<path>`). Finally add the library to `REPO.md` and `README.md`. Everything else — build, testspace copy, release, bump, version — is generic.

### Generated files — do not edit

- `test/build/*.md`, `test/test/**` — gitignored build output
- `releases/<Page>.md`, `releases/<Page>.VERSION`, the files of `<lib>_FILES` under `releases/` — committed, but only ever written by `make release`

## Source layout and assembly order

Building `<lib>` concatenates, in this exact order, into one page:

1. `src/<lib>/frontmatter.md` — page frontmatter (`name: Library/Finestream/<Page>`, `tags: meta/library`)
2. an autogenerated "do not edit" note
3. `$(<lib>_DOCS)` — user-facing docs (features, config reference, command list); ends with a `## Code` heading that the code block falls under
4. `$(<lib>_LUA)`, wrapped in a single ` ```space-lua ` fence

Consequences: for kanboard, `library.lua` is loaded before `kanboard.lua` and `views.lua` last, so `Kanboard.*` may call `Library.*` freely; the fragments of a library share one global Lua scope; and any user-visible change must be documented in the library's docs page in the same edit, since that file *is* the library's documentation.

`Library` (in `src/kanboard/library.lua`) is the generic, Kanboard-agnostic layer: UUIDs, frontmatter read/write, "subtree" and "current task" extraction, page creation, plus the `pageId:` virtual page and `/idea`. `Kanboard` (in `kanboard.lua`) is the integration layer. Keep new reusable editor/page helpers in `Library`. **`library.lua` ships only with kanboard** — a user may install any subset of the libraries, so every other library must be self-contained (installing two copies of `Library` would define its commands, slash commands and virtual pages twice).

Empty `kanboard/` and `scripts/` directories at the repo root are vestigial.

## Kanboard integration architecture

**Transport.** All Kanboard access goes through `Kanboard.rpc(method, params)` → JSON-RPC POST to `<kbBaseUrl>/jsonrpc.php` via `net.proxyFetch` with Basic auth from `kbUsername`/`kbToken`. Every call site checks `Kanboard.checkResponse(response)` (which also emits debug notifications at verbosity 4) and bails with `Library.notify(Library.ERROR, ...)` on failure. Follow that pattern rather than inventing new error handling.

**Notifications** go through `Library.notify(level, message)`, never `editor.flashNotification` directly: `Library.ERROR` (1) for failures, `Library.WARNING` (2) for something the user should know but that did not fail, `Library.INFO` (3) for success messages, `Library.DEBUG` (4) for diagnostics. A message is shown when the configured verbosity is at least its level. `Library.verbosity()` returns the default (1); `kanboard.lua` replaces it with `Kanboard.verbosity`, which reads `config.get("kanboard").verbosity` and falls back to `debug = true` meaning 4, so `Library` itself stays Kanboard-agnostic. Never gate control flow on the verbosity: a `return` inside `if <debug> then` changes what the code does depending on how chatty it is.

**Config** lives in the user's `CONFIG` page under the `kanboard` key, read with `config.get("kanboard")`: `kbBaseUrl`, `sbBaseUrl`, `kbUsername`, `kbToken`, `kbProjectId` (default project), `sbCachePath`, `sbCacheRefreshHours`, `kbCloseDone`, `kbMoveDone`, plus optional `verbosity` (0–4, default 1; the older `debug = true` means 4) and optional `taskTable` (the task table, below). `make testspace` generates an equivalent CONFIG.md from the `KB_*`/`SB_*` env vars, so a new config key must be added in three places: `kanboard.md` docs, the `testspace` target, and `.env.example` if it should be settable per-developer.

## ImageGallery architecture

**Nothing is stored.** `ImageGallery.imageGallery(directory, cols, rows, width, height)` lists the space with `space.listDocuments()` on every render, keeps the images sitting directly in `directory` (non-recursive), and builds the grid as real DOM nodes through the Std `dom` API, returned as a block `widget.new`. The only thing written to a page is the `${ImageGallery.imageGallery(...)}` directive that the insert command and `/imageGallery` leave behind.

**Thumbnails** are `<img loading="lazy">` with `object-fit: contain` inside a fixed `width` x `height` flex box, so an image fits its bounding box without being cropped or stretched, and the thumbnails of gallery pages that are not on screen are never fetched. Image URLs come from `ImageGallery.documentUrl` (`.fs/<path>`, colons escaped) — the same endpoint the editor uses for transclusions, relative to the client's `<base href>`.

**Pagination happens in the browser.** The grid of a gallery page is built the first time that page is shown, and paging only toggles `style.display` — no page rewrite, no re-render. Because SilverBullet re-renders widgets while the document is edited, the visible page number is parked in `ImageGallery.state[directory|cols|rows]` so a re-render resumes where the reader was.

**Full size view.** The `imageGallery:(.+)` virtual page renders `imageGallery:<path>:view`. The `:view` suffix exists so the reference does not end in an image extension — SilverBullet would otherwise resolve it to the document itself instead of the virtual page. Paths containing `@ # | < > $` cannot be expressed as a reference at all (`ImageGallery.viewRef` returns nil), and thumbnails then link to the document.

**Config** lives under the `imagegallery` key, read with `config.get("imagegallery", {})` and merged over `ImageGallery.defaults`: `directory`, `cols`, `rows`, `width`, `height`. All of it is optional — the library must keep working with no CONFIG at all. `make testspace` generates the section from the `IG_*` env vars, and `test/space/Images/` holds eight solid-colour PNGs of assorted aspect ratios plus `test/space/Gallery.md` to exercise the paginated, single-page, default and empty-directory cases by hand.

**The cache is the data model.** Kanboard is the source of truth; SilverBullet holds a mirror as ordinary markdown pages at `<sbCachePath>/<projectId>`, tagged `KanboardManaged`. Each Kanboard task becomes one SilverBullet task line built by `Kanboard.buildCacheEntry` — the single point of maintenance for the cache format:

```
* [ ] Title ([KB](url)) #<tag> #<category-Name> [kbId: 42] [column: Doing] [projectId: 2] [due: …] [swimlaneId: …] [pageId: …]
```

Those bracketed attributes are what SilverBullet's indexer exposes, so all lookups are `query [[from index.tasks() where kbId == … ]]`-style queries over the cache — never RPC calls. Changing an attribute name silently breaks every query in `kanboard.md`, the slash commands, and users' pages. Angle brackets are stripped from tags/category names (`Library.escapePattern`) because they cannot be escaped in SilverBullet tags.

**Cache refresh** (`Kanboard.updateCache(projectId, kbTask)`) is deliberately two-mode: with no cache page, a stale one (`lastSync` older than `sbCacheRefreshHours`), or no `kbTask`, it does a full `rebuildCache` (one `getAllTasks` call); otherwise `updateCacheEntry` rewrites just that task's line in place. Keep both paths working. Note `buildCacheEntry` still issues one `getTaskTags` RPC per task, so rebuilds are O(tasks) round trips.

**Page identity.** Pages get a `pageId` UUID in frontmatter; Kanboard tasks store it in their `reference` field and get an external link to `<sbBaseUrl>/pageId:<uuid>`. The `virtualPage` handler for `pageId:(.+)` resolves that back to a page and navigates, so links survive page renames. Never key anything off page names.

**Round trip.** `Kanboard: Send Task` (`Ctrl-Alt-a` / `Ctrl-Cmd-a` on mac) takes the task under the cursor, creates it in Kanboard, then *replaces the source line with a live query* (`Kanboard.queryTask`) that renders the cached copy — so after sending, the page no longer owns the task text. Project/swimlane come from page frontmatter (`kbProjectId`, `kbSwimlaneId`) falling back to config. `Kanboard: Sync Status` pushes locally-completed tasks back (close and/or move to the last column per `kbCloseDone`/`kbMoveDone`), and `Kanboard: Remove Cache` deletes all `KanboardManaged` pages after an `editor.confirm`.

**Task table.** `views.lua` holds `Kanboard.views`, what pages call: `Kanboard.views.tasks(rows, columns)` renders any query over tasks as a table with a done/open button, sorting, per-column filters and a search field. Four things are deliberate:

- **Everything it receives is data.** Task texts, page names, attribute values and column lists reach the page through `Kanboard.views.node` (a text node) or as attribute values, never as a string child of `dom.*`. Links in a task text are made by `Kanboard.views.inline` from three patterns, and an external link only for `http`, `https` and `mailto`. The made-up cache page `test/space/Kanboard/900.md` has a task that tries, and `test/space/Tasks.md` shows it; keep both.
- **It is not a `<table>`** but `div`s laid out with `display: table`, so that a library that decorates every `<table>` of the client does not add a second set of sort and filter controls. The look is the `space-style` block in `kanboard.md` (classes `kanboard-tasks-*`), on SilverBullet's own table colours (`--editor-table-head-*`).
- **The button changes a state marker and nothing else.** `Kanboard.views.toggle` finds the task in the index by page and position under the name the table shows, checks the marker in the page text, and then calls SilverBullet's own `index.updateTaskState`. A row a page made up ends at the first check. Nothing is sent to Kanboard on a click: a done task of the cache goes with the next `Kanboard: Update Cache` (`closeTasks`). A task's `pos` is the 0-based offset of its list marker, so the state is at `pos + 3`.
- **Sorting, search and filters happen in the browser,** on rows built once, and are parked in `Kanboard.views.state` (keyed by page, columns and tasks) so a re-render keeps them, as ImageGallery does.

Its configuration is the `taskTable` section of the `kanboard` key (`Kanboard.views.defaults`), in the column format of the third-party TaskManager library it replaces: `{header, attribute, format}`.

## ITAM architecture

**Nothing is stored.** Every view is computed from the index when a page is shown; the library writes nothing but the pages created from its templates.

**One namespace, built in this order:** `itam.lua` (`ITAM`: configuration, lists, helpers, the tag schemas), `backup.lua` (`ITAM.backup`: the chain), `views.lua` (`ITAM.views`: what pages call), and `decisions.lua`, which adds the `dr` tag and the decision views and so comes last. A page calls `ITAM.views.*` only; a space that restricts what pages may call needs nothing else on its allowlist. So a new function a page should call goes on `ITAM.views`, and everything else on `ITAM` or `ITAM.backup`.

**Config** lives under the lowercase `itam` key, like `kanboard` and `imagegallery`, read with `config.get("itam", {})` and merged over `ITAM.defaults` by `ITAM.config()`; all of it is optional. No value of a particular space belongs in the code, the templates or `test/space/`. The schemas take the configured lists as enums when the library loads, and `validate` checks them again when a page is indexed, so a change to `CONFIG` needs `System: Reload`, then `Space: Reindex`. `make testspace` generates the section from the `ITAM_*` env vars (`ITAM_JOB_STATUSES` and `ITAM_DR_STATUSES` give the test space a `status` on jobs and a seventh decision status, `draft`, so that an override is always exercised), and `test/space/Computer/` holds a small made-up set-up with one page per kind.

**Types are defined once.** `ITAM.types` holds the defaults per kind; an entry is a name or a table with a name and properties (`copy`, `inPlace`, `policy` for a job). `buildTypes()` turns those and `types.<kind>` into what `ITAM.typesOf(kind)` and `ITAM.definitionOf(kind, name)` return, once, when the library loads. So code asks a job type for its property and never names `"backup"` or `"snapshot"`. `-- priority: -10` on the first line of `itam.lua` is what makes the configuration complete by then: without it, a `config.set` on a page that sorts after `Library/` reaches `validate` but not the schema enums. SilverBullet takes the first `-- priority:` it finds in the block, so that text must not appear earlier.

**Status values are configuration too.** `ITAM.defaults.statuses` holds, per kind, the allowed `status` values (a list: required, one of them; `{ values, optional = true }`: may be left out; `false`: no `status`), and `ITAM.defaults.dr.statuses` the lifecycle of a decision as entries with properties (`dot`, `active`, `provisional`), merged by name like the types. `ITAM.config()` normalises a kind to `{ values, optional }` or nil, `ITAM.statusOf(kind)` returns the copy taken when the library loads (like `ITAM.typesOf`, so `validate` does not re-read `CONFIG` per page), and `buildDrStatuses()` derives `ITAM.drStatuses`, `ITAM.drDots`, `ITAM.drActive` and `ITAM.drStatusOf(name)` once, through the same `definitionsOf` merge as the types. `object(kind, …)` adds the `status` property and the requirement to a schema from that, `checkStatus` validates it at index time, `ITAM.views.index` appends the column only for a kind with `status`, and the templates carry `${ITAM.statusLine(kind)}` instead of a literal line, which expands to nothing for a kind without `status` (the indented line stays, empty). So no `.lua`, template or docs file names a status value outside `ITAM.defaults`. One trap: a list from `config.get` is a JS array, and `entries.values` on it is the array's *method*, not nil, so `statusSpec` ignores a function there and recognises the table form only when the entry has no first element.

**Templates** are the files of `itam_FILES`, installed under `Library/Finestream/ITAM/Templates/`. Their paths and allowed values come from `ITAM.pagePrefix()`, `ITAM.hint()`, `ITAM.statusLine()` and `ITAM.drDefault()`. Their commands are `ITAM: New <Kind>`.

**The page name** is `ITAM`. SilverBullet refuses an install with `Page already exists` if `Library/Finestream/<Page>` is present anywhere in the space, in any case, also as the end of a longer path such as `Archive/library/finestream/<Page>`: `space.pageExists` uses `resolvePath` (`plug-api/lib/resolve_path.ts`), which matches by a case-insensitive suffix. The same applies to every library. The templates sit in a folder named after the library, so that `releases/` and `Library/Finestream/` stay per library.

**Tags** are set on the commit that holds the release files: `make release-<lib>` tags `HEAD`, which is the commit before them, so after the merge the tag is set again on the merge commit and only then pushed.

## Utilities architecture

**Lowercase namespace on purpose.** The global is `utilities` (not `Utilities`), because pages call `utilities.tagCloud()`, `utilities.health()` and `utilities.proposals()` and those exact names are what a restricted space puts on its allowlist. `utilities = utilities or {}` keeps an older definition of the same table from breaking the load order either way.

**Health checks are rows.** `utilities.checks` lists every row of `utilities.health()`; a check either has a `rows` function (its detail, whose length is the count, shown on the virtual page `health:<detail>`) or a `report` field read from the MCP server's report page through the index (`utilities.mcpReport`). Table and detail page call the same function. A `rows` function returning nil hides the check (decisions due for review without ITAM, pages waiting for review without `proposedPrefix`, status without a schema when no tag defines `status`). *Status without a schema* names no tag: `utilities.statusTags()` reads the `tag.define` definitions (`config.get("tags")`) for a schema with a `status` property, so it follows ITAM's configured `statuses` (a kind set to `false` has no such property, and a page of that kind with a `status` is listed) and works without ITAM.

**Output is markdown, made inert.** Every value from the space goes through `utilities.code` (a code span sized against backtick runs, `|` escaped) or `utilities.link` (a wiki link only when `utilities.safeName` holds). A virtual page's markdown is rendered like a page, so a raw `${…}` or HTML in it would run.

**The tag cloud is a block widget with a class, styled by the library.** `utilities.tagCloud()` returns `widget.new { markdown, display = "block", cssClasses = { "utilities-tag-cloud" } }`; the class lands on the `.sb-lua-directive-block` wrapper. SilverBullet draws every wiki link with `padding: 0 5px; margin: 0 -5px`, so links separated by a space touch, and its rule is `#sb-main .cm-editor .sb-lua-directive-block a.wiki-link`. The `space-style` block in `utilities.md` therefore selects `#sb-main .cm-editor .sb-lua-directive-block.utilities-tag-cloud a.wiki-link`: a selector without the id and `.cm-editor` loses on specificity and changes nothing, silently.

**No value of a particular space in the defaults:** `exclude` defaults to `Library/` only and `proposedPrefix` has none; `make testspace` sets both from `UT_EXCLUDE`/`UT_PROPOSED_PREFIX`.

**Proposals** (`proposals.lua`) read a page tagged `proposal` (`target`, `outcome`, pairs of `~~~~expected`/`~~~~replacement` fences), run the stale check (every expected text exactly once) and write the target with `space.writePage` when the person clicks *Apply*. The diff is jsdiff, vendored under `src/utilities/vendor/` and carried base64-encoded in the generated `jsdiff.lua` (`make vendor-utilities`), imported from a `data:` URL: Space Lua cannot hold the minified code in a long bracket string. `utilities.recentOutcomes` covers the moment between writing an outcome and the index learning about it, so a proposal leaves the list on click and its review shows the outcome.

**The formatted diff colours lines, not blocks.** `formattedDiff` splits the page into blocks at blank lines *and* at headings (a decision record puts its list directly under `## Decision`, so heading and list would otherwise be one block), diffs the blocks with jsdiff, and compares each changed block line by line (`lineDiff`), a changed table row by row (`tableDiff`); a run of removed blocks followed by a different number of added ones is compared line by line as a whole. Striking a whole block for one changed line made the view far noisier than the change.

**The list and the review are two pages.** `utilities.proposals()` is a table of the open proposals with *Apply all* and no diff (a page with several proposals was overwhelming); each row links to the virtual page `proposal:<name>`, whose markdown is a heading plus `${utilities.review()}`. The widget takes the proposal name from `editor.getCurrentPage()` (a virtual page returns its own name), never from the markdown, so no page name is written into a Lua string literal. Virtual pages do evaluate `${…}` directives on 2.12.1, which is what makes a DOM widget with buttons possible there.

**String children of the `dom` API are rendered as markdown** (`dom.td { "# x" }` becomes a heading, `[[x]]` a link). Text from a page goes in as a text node (`utilities.el`), never as a string child.

**A page with conflict markers keeps only its name in the index** (SilverBullet 2.12 skips frontmatter, tags, tasks and links of such a page), which is why the conflict check reads page texts with `space.readPage`.

## Conventions

- Lua indented with **tabs**; every function and every `command.define`/`slashCommand.define`/`virtualPage.define` is preceded by a 71-dash banner comment documenting behaviour, returns, and workflow steps. Match this — it is the only documentation of the API surface.
- **Never put `markdown` and `html` in the same `widget.new` spec.** On SilverBullet 2.9 the `markdown` key is rendered *instead of* `html`, so a DOM widget silently collapses into whatever the markdown says — with no error. (`main` documents the opposite precedence, `html` for display and `markdown` for the Copy/bake body; do not trust that until the target version ships it.) The cost of leaving `markdown` out is only that Copy falls back to `outerHTML`.
- **`markdown.markdownToHtml` renders a paragraph as an inline `<span class="p">`, not a `<p>`.** Joined strings of its output flow into each other and around anything inline (an SVG); wrap each joined part in a block element, as `compose` in `src/itam/views.lua` does.
- **A string child of a `dom.*` spec is rendered as markdown,** with `expand`, and inserted as HTML (`Library/Std/APIs/DOM`). Text that is data (a task title, a page name, a configured label) goes in as `__rawText` or a text node, as `Kanboard.views.node` does.
- **JS arrays and DOM collections are 1-based from Lua.** `luaGet` subtracts one internally, so a `NodeList` is `nodes[1]`..`nodes[n]`; writing `nodes[i - 1]` reads one before the start and yields nil.
- **Never chain a method call onto a call that returns multiple values.** Space Lua represents a multi-value result as one opaque value, so `s:gsub("a", "b"):gsub("c", "d")` dies at runtime with `attempt to index a userdata value` — and wrapping it in parentheses does *not* truncate it either, unlike real Lua. Assign to a local between the two calls. Chaining onto a single-return call (`s:match(...):upper()`) is fine, and a multi-return used as a concatenation or argument operand is fine. Standard `luac -p` cannot catch this, which makes it the easiest way to ship a broken library.
- Commands are named `"<Library>: <Title Case>"`; slash commands are lowerCamelCase.
- SilverBullet globals (`config`, `net`, `encoding`, `editor`, `query`, `space`, `command`, `slashCommand`, `virtualPage`, `js`, `yaml`, `dom`, `widget`) are declared in `.vscode/settings.json` under `Lua.diagnostics.globals` — add new ones there when used. That file is gitignored, so it may be absent in a fresh clone.
- Commit messages use informal prefixes seen in history (`Feature ...`, `bug fix: ...`, `Cosmetic: ...`, `Refactoring ...`).
