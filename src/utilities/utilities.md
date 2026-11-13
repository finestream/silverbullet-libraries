
# Utilities

Space-wide views that belong to no other library: a tag cloud, a health
table that counts what needs attention in a space, with a detail page per
check. Change proposals are not part of it: the Proposals library of the
[SilverBullet MCP server](https://github.com/finestream/silverbullet-mcp-server)
lists, reviews and applies them (`${proposals.list()}`).

Nothing is stored: every view is computed from the index and the pages when it
is shown. Pages call `utilities.tagCloud()` and `utilities.health()` only, so a
space that restricts what pages may call needs just these two entries on its
allowlist.

**Upgrading from 0.x:** `utilities.proposals()`, `utilities.review()` and the
virtual page `proposal:<name>` are gone. Replace `${utilities.proposals()}` on
your pages with `${proposals.list()}`, and drop `utilities.proposals` and
`utilities.review` from the allowlist. Links `[[proposal:<name>]]` no longer
resolve (they show up as aspiring pages): make them `[[review:<name>]]`. The
*Open proposals* row reads the index, so after a click in a review it lags
until the index has caught up.

## Features

* *Tag cloud* every tag of the space once, alphabetically, as links to its tag
  page.
* *Health table* one row per check with its count and a link to its detail:
  * *MCP scan: findings* and *files that are not pages*: the counts from the
    report page of the [SilverBullet MCP server](https://github.com/finestream/silverbullet-mcp-server)'s
    scan, and whether it blocks rendering;
  * *Conflicts*: `.conflicted` copies and, if `conflictMarkers` is on, pages
    with conflict markers;
  * *Aspiring pages*: links to pages that do not exist;
  * *Invalid frontmatter*: formal pages whose frontmatter fails validation;
  * *Status without a schema*: pages with a `status` that no schema checks;
  * *Capitalised Status*: pages whose frontmatter says `Status` instead of
    `status`;
  * *Decisions proposed* and *due for review*: decision records (`#dr`);
  * *Tasks overdue* and *without due date*: open tasks of the Kanboard
    library's cache;
  * *Pages waiting for review*: pages in a configured folder (for example
    where agents write) that have been `proposed` for too long.
  * *Open proposals*: change proposals of the Proposals library that are open,
    each linked to its review page, and the target it changes.
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
* *Conflicts*: page and file names containing `.conflicted`, from the index.
  With `conflictMarkers = true` also the text of every page that is not
  excluded, for a line starting with `<<<<<<<` followed by `=======` and
  `>>>>>>>`. SilverBullet indexes only the name of a page with conflict
  markers, so the text has to be read. That is why it is off by default: with
  it off the health table reads no page text, and a user who may not read
  every page (an agent, say) can still render a page that shows the table.
* *Status without a schema*: pages with a `status` in their frontmatter and
  no tag whose definition (`tag.define`) has a schema with a `status`
  property. The tags are read from the definitions, not listed here: with the
  ITAM library they are `dr` and every kind configured with a `status`. No
  schema checks such a value, so a query on `status` cannot rely on it. In a
  space where no tag defines `status` the field is free and the row is not
  shown.
* *Capitalised Status*: pages with a `Status` key. YAML keys are
  case-sensitive, so this is another field than `status`: no schema checks it
  and a query on `status` misses the page.
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
* *Open proposals*: pages tagged `change-proposal` under the Proposals
  library's folder (its `proposals.proposalPrefix`, default `Proposals/`)
  whose `outcome` is `open` or missing. The detail page shows each proposal's
  name as a link to its review page `review:<name>` (written as the alias link
  `[[review:<name>|<name>]]`, so the cell shows the name). The target is the proposal's
  `target`: a wiki link in quotes (`"[[Notes/Garden]]"`) is shown as the link,
  a plain name as a link too, and a number or a boolean as a code span. Any other
  value (a list, a map) leaves the cell empty. The row is hidden when
  `proposals.proposalPrefix` is set to an empty or non-string value, so a space
  without the Proposals library can turn it off that way.

## Configuration

Configuration is optional; without it every view works, and only the checks
*Pages waiting for review* (without `proposedPrefix`) and *Open proposals*
(with `proposals.proposalPrefix` set to `""`) are not shown. To change the defaults, add the
following section to your `CONFIG` page in a space-lua block:

```lua
config.set {
  utilities = {
    exclude = { "Library/" },   -- pages left out of every view (default)
    mcpPage = "MCP Server",     -- report page of the MCP server's scan (default)
    proposedPrefix = "Drafts/", -- folder of pages waiting for review (no default)
    proposedDays = 7,           -- days a page may wait in `proposed` (default)
    conflictMarkers = true,     -- read every page for conflict markers (default: false)
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

The cloud is a block with the CSS class `utilities-tag-cloud`; its look is the
style block below, which a `space-style` block of your own can override. The
links are spaced out, because SilverBullet draws a wiki link with a padding
and the same negative margin, so that links separated only by a space touch.

### Health

```
${utilities.health()}
```

The *Detail* column links to the check's detail page, for example
`[[health:aspiring]]`; the MCP rows link to the report page.

## Style

```space-style
/* The tag cloud: wiki links in a row, spaced out. SilverBullet gives a
   wiki link a padding and the same negative margin, so that a space
   between two links is all the distance there is. Its rule is
   `#sb-main .cm-editor .sb-lua-directive-block a.wiki-link`; this one
   names the widget's own class as well, so it wins. */
#sb-main .cm-editor .sb-lua-directive-block.utilities-tag-cloud a.wiki-link {
  display: inline-block;
  margin: 0 0.6em 0.5em 0;
  padding: 0.1em 0.5em;
}
```

## Code
