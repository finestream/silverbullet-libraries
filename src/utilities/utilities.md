
# Utilities

Space-wide views that belong to no other library: a tag cloud, a health
table that counts what needs attention in a space, with a detail page per
check, and change proposals: edits to a page that someone else (typically an
agent without write access to that page) proposes, and that you review as a
diff and apply with one click.

Nothing is stored beyond what you apply: every view is computed from the index
and the pages when it is shown. Pages call `utilities.tagCloud()`,
`utilities.health()` and `utilities.proposals()` only, so a space that
restricts what pages may call needs just these three entries on its allowlist.

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
  * *Open proposals*: change proposals that are open or stale.
* *Detail pages* `health:<check>` lists the pages behind a count, as links.
* *Change proposals* a list of the open proposals (target page, number of
  changes, task, state), with *Apply all* for every listed proposal after one
  confirmation. Each entry links to its review page `proposal:<name>`, which
  shows the proposal's reason and its change the way GitHub shows a diff of a
  Markdown file: *Formatted* (the page as it will look; only the changed
  lines are struck through on red or added on green, a changed table only
  its changed rows, and headings, lists and paragraphs around them stay as
  they are) or *Text* (the source lines, with the changed words highlighted). *Apply* writes the change to the page
  with your rights, *Edit* opens the proposal so you can change the proposed
  text first, and *Reject* drops it.
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
* *Open proposals*: pages tagged `proposal` whose `outcome` is `open`,
  missing or `stale`.

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

### Proposals

```
${utilities.proposals()}
${utilities.proposals("Some/Page")}
```

The first lists every open proposal, the second only those for one page (put
it on that page to see what is waiting for it). The list holds no diff: each
entry links to the review page `proposal:<name of the proposal page>`, a
virtual page with the reason, the diff and the buttons. `[[proposal:Some/Proposal]]`
links to a review from any page. The review page calls `utilities.review()`,
which takes the proposal from the page shown; a space that restricts what
pages may call needs no entry for it, because a virtual page is not a file,
but `${utilities.review("Some/Proposal")}` on a page of your own needs
`utilities.review` on the allowlist.

A proposal is a page tagged `proposal`. Its frontmatter names the page to
change, and its body holds the reason as text and then one pair of fenced
blocks per change: the text as it is now, and the text that replaces it.
Use four tildes, so the blocks can contain backticks and code fences.

```markdown
---
tags: proposal
target: "[[Notes/Garden]]"
outcome: open
---
Watering moved to the morning.

~~~~expected
Watering is done in the evening.
~~~~
~~~~replacement
Watering is done early in the morning.
~~~~
```

* **Stale check.** Every expected text must occur exactly once in the target
  page, when the proposal is shown and again when it is applied. Otherwise the
  proposal cannot be applied, and shows why; *Close as stale* records that.
  Nothing is matched approximately: the author writes a new proposal.
* **Outcome.** *Apply*, *Reject* and *Close as stale* record `applied`,
  `rejected` or `stale` in the proposal's `outcome`; only `open` (or no
  `outcome`) and `stale` proposals are listed. Proposal pages are never
  deleted by the library.
* **Nothing runs before you apply.** The formatted view is rendered by
  SilverBullet's own Markdown renderer, which shows `${...}` as text and drops
  scripts and event handlers; the text view is plain text. The proposed text
  runs only once it is in the page, like anything you write yourself.
* **The diff** is computed by [jsdiff](https://github.com/kpdecker/jsdiff)
  (BSD-3-Clause), which is part of the library: nothing is loaded from the
  network.

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
