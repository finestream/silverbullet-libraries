
# Utilities

Space-wide views that belong to no other library: a tag cloud, and a health
table that counts what needs attention in a space, with a detail page per
check.

Nothing is stored: every view is computed from the index when the page is
shown. Pages call `utilities.tagCloud()` and `utilities.health()` only, so a
space that restricts what pages may call needs just these two entries on its
allowlist.

## Features

* *Tag cloud* every tag of the space once, alphabetically, as links to its tag
  page.
* *Health table* one row per check with its count and a link to its detail:
  * *MCP scan: findings* and *files that are not pages*: the counts from the
    report page of the [SilverBullet MCP server](https://github.com/finestream/silverbullet-mcp)'s
    scan, and whether it blocks rendering;
  * *Conflicts*: pages with conflict markers and `.conflicted` copies;
  * *Aspiring pages*: links to pages that do not exist;
  * *Invalid frontmatter*: formal pages whose frontmatter fails validation;
  * *Decisions proposed* and *due for review*: decision records (`#dr`);
  * *Tasks overdue* and *without due date*: open tasks of the Kanboard
    library's cache;
  * *Pages waiting for review*: pages in a configured folder (for example
    where agents write) that have been `proposed` for too long.
* *Detail pages* `health:<check>` lists the pages behind a count, as links.
* *Safe output* text from the space (page and tag names, frontmatter values,
  error messages) is never written into the page as is: a page name becomes a
  link only when it cannot break out of one or start like a URL
  (`javascript:`), everything else is shown in a code span, where SilverBullet
  evaluates no directive and renders no HTML.

## Formal and informal pages

A page is *formal* when one of its tags is defined with `tag.define` and a
`schema` or a `validate` function (the ITAM library defines such tags);
every other page is *informal*, with free frontmatter, and is never counted by
*Invalid frontmatter*. Each such tag is checked as the editor's lint does:
`jsonschema.validateObject` with the schema, then `validate`. A tag defined
with `mustValidate = true` keeps a failing page out of the index altogether,
so this check cannot see such a page.

## Where each check reads its data

* *MCP scan*: the headings `Findings (N)` and `Files that are not pages (N)`
  and the list item `Rendering: …` of the report page (`mcpPage`), read from
  the index. Without that page both rows say *no report*.
* *Conflicts*: page and file names containing `.conflicted`, and the text of
  every page that is not excluded, for a line starting with `<<<<<<<`
  followed by `=======` and `>>>>>>>`. SilverBullet indexes only the name of
  a page with conflict markers, so the text has to be read.
* *Decisions*: pages tagged `dr`. *Proposed* means `status: proposed`. *Due
  for review* uses the ITAM library's rule and setting (an active status, and
  `lastReviewed` missing or older than its `reviewDays`); without ITAM the row
  is not shown.
* *Tasks*: tasks with a `kbId` (the Kanboard library's cache) that are not
  done; *overdue* means a due date before today, *without due date*
  `dueRaw == 0`.
* *Pages waiting for review*: pages under `proposedPrefix` with
  `status: proposed` whose frontmatter `date` (or, without one, the last
  change) is more than `proposedDays` days ago. Without `proposedPrefix` the
  row is not shown.

## Configuration

Configuration is optional; without it every view works, and only the check
*Pages waiting for review* is not shown. To change the defaults, add the
following section to your `CONFIG` page in a space-lua block:

```lua
config.set {
  utilities = {
    exclude = { "Library/" },   -- pages left out of every view (default)
    mcpPage = "MCP Server",     -- report page of the MCP server's scan (default)
    proposedPrefix = "Drafts/", -- folder of pages waiting for review (no default)
    proposedDays = 7,           -- days a page may wait in `proposed` (default)
  }
}
```

`exclude` applies to the tag cloud (tags that occur only on excluded pages),
to the pages that link to aspiring pages, and to every other check.

## Usage

### Tag cloud

```
${utilities.tagCloud()}
```

Tags starting with `meta` are left out, as are tag names that hold a
character that could break the link (`[ ] | { } $ < >` or a backtick) or
that starts like a URL scheme (`name:`).

### Health

```
${utilities.health()}
```

The *Detail* column links to the check's detail page, for example
`[[health:aspiring]]`; the MCP rows link to the report page.

## Code
