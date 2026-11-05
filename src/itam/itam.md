
# ITAM

IT asset management: document a set-up as pages: hosts, services, networks, storage, policies, jobs
and the decisions behind them. One page per object, with its facts in the
frontmatter; the library validates the frontmatter against a schema per kind,
and every page ends with one call that shows what is derived from the other
pages: the services and storage of a host, the backup chain of a storage, the
members of a network, the objects a decision governs. Diagrams and index
tables are generated, never drawn by hand.

Nothing is stored: every view is computed from the index when the page is
shown. The library writes nothing but the pages you create from its templates.

## Features

* *One object, one page* each object carries its own tag (`host`, `service`,
  `network`, `storage`, `policy`, `job`, `dr`) next to the tag `component`,
  and a `type` field. Relations are frontmatter links: `partOf`, `on`,
  `network`, `exposedVia`, `authVia`, `dependsOn`, `policies`, `source`,
  `target`, `implements`, `decision`.
* *Schemas* one `tag.define` per kind checks the fields and the allowed
  values, and decorates the page with an icon for its kind (a status dot for
  a decision). A broken page shows a lint warning in the editor.
* *Views* every object page ends with `${ITAM.views.page(_CTX.currentPage.name)}`,
  which looks at the page's tags and shows the view for its kind, so a page
  that changes kind needs no edit.
* *Backups as storage, policies and jobs* copy jobs (by default `backup`,
  `snapshot`, `sync`) copy from a `source` storage to a `target` storage and `implements`
  the policy they fulfil. The chain is never written down: the storage view
  follows source → job → target and counts the copies, the original included.
  A copy is offsite when it sits at another site than the original or on a
  host of type `external`, so storage on an `external` host is offsite itself.
* *Index pages and diagrams* `ITAM.views.index(tag)` lists every object of one
  kind, `ITAM.views.copies()` the copies of every protected storage,
  `ITAM.views.architecture()` draws the hosts by site with the networks they are
  on, `ITAM.views.decisions {…}` draws the decisions as a graph.
* *Decision records* the tag `dr` after the ADR pattern: `status`
  (`proposed` → `provisional` → `accepted`, then `superseded` or `deprecated`;
  `rejected` is a dead end), `area` (one value or a list), `deciders`, `owner`, `lastReviewed`,
  `supersedes`, `dependsOn`, `related`. Two views list what needs attention:
  `ITAM.views.drDueForReview()` and `ITAM.views.drProvisional()`.
* *Page templates* one command per kind (`ITAM: New Host`, `ITAM: New Service`,
  `ITAM: New Storage`, `ITAM: New Network`, `ITAM: New Policy`, `ITAM: New Job`, `ITAM: New Decision`)
  creates a page with the right fields, the allowed values as comments, and
  the view call.

## Suggested workflow

* Put the objects in one folder per kind: `Computer/Host/`,
  `Computer/Service/`, `Computer/Storage/`, `Computer/Network/`,
  `Computer/Policy/`, `Computer/Job/`, `Computer/Decision/`. The page name is
  the object's name; the host is never part of the path, only of `partOf`.
* Next to each folder, an index page with `${ITAM.views.index("host")}` and so on;
  the policy index adds `${ITAM.views.copies()}`; the entry page `Computer` shows
  `${ITAM.views.architecture()}`.
* Create new pages with the templates (`ITAM: New Host`, …), fill in the
  frontmatter, keep the prose for what no field can hold: why, how, caveats.
* Every storage has at least one policy, the layers below the data included;
  a *no backup* policy says that nothing protects it.
* Record decisions with `ITAM: New Decision`; an index page with
  `${ITAM.views.decisions { statuses = { "accepted", "provisional" } }}`,
  `${ITAM.views.drDueForReview()}` and `${ITAM.views.drProvisional()}` shows where they
  stand.

## Configuration

Configuration is optional: without it, the objects are expected under
`Computer/`, any `location` and `area` is accepted, and the default type
lists apply. To adapt the library to your space, add the following section
to your `CONFIG` page in a space-lua block; every key may be left out:

```lua
config.set {
  itam = {
    roots = { "Computer/" },           -- page prefixes the views consider
    pagePrefix = "Computer/",          -- where the templates create pages (default: the first root)
    sites = { "Home", "Office" },      -- allowed `location` values; {} allows any text
    providers = "Providers",           -- the group of the hosts of type external in the architecture diagram
    types = {                          -- a list here replaces the default list of that kind
      host = { "server", "nas", "mac", "pc", "pi", "mobile", "appliance", "external", "unused" },
      job = {                          -- an entry is a name, or a table with a name and properties
        "backup", "snapshot", "sync",
        { name = "mirror", copy = true, policy = "replication" },
        "update", "test", "scrub", "script",
      },
    },
    dr = {
      tagPage = "Computer/Decision",   -- the page the `dr` tag opens
      areas = { "infrastructure", "knowledge" }, -- allowed `area` values, one or a list per decision; {} allows any text
      deciders = "@me",                -- `deciders` of a new decision
      owner = "@me",                   -- `owner` of a new decision
      reviewDays = 180,                -- a decision is due for review this many days after lastReviewed
    },
  }
}
```

The default type lists, in the order the views sort by:

| Kind | Values |
| --- | --- |
| `host` | `server`, `nas`, `mac`, `pc`, `pi`, `mobile`, `appliance`, `external`, `unused` |
| `service` | `container`, `package`, `system`, `app`, `external` |
| `storage` | `hdd`, `ssd`, `sd-card`, `usb-stick`, `raid`, `luks`, `lvm-pv`, `lvm-vg`, `lvm-lv`, `volume`, `share`, `folder`, `repository`, `cloud` |
| `network` | `lan`, `tailnet`, `internet`, `docker-bridge`, `docker-macvlan` |
| `policy` | `backup`, `snapshot`, `retention` |
| `job` | `backup`, `snapshot`, `sync`, `update`, `test`, `scrub`, `script` |
| `auth` (of a service) | `keycloak`, `forward-auth`, `own`, `none`, `n/a` |

### job types and policy types

Each job type is defined once, with what it means; nothing else repeats it.
These are the defaults:

| Job type | `copy` | `inPlace` | `policy` |
| --- | --- | --- | --- |
| `backup` | yes | | `backup` |
| `snapshot` | yes | yes | `snapshot` |
| `sync` | yes | | `backup` |
| `update`, `test`, `scrub`, `script` | | | |

* `copy`: the job counts as a copy from `source` to `target`: the backup chain
  follows it, and it needs a `source`.
* `inPlace`: the copy stays on the source, so it needs no `target`, and any
  `target` it lists is ignored. Without it, a copy job needs a `target`.
* `policy`: the policy type that governs the job. It is always an allowed
  policy type, added after the ones in `types.policy` if they leave it out. The
  library does not check `implements` against it.

An entry named like a default keeps that default's properties, so listing
`"backup"` as a name is enough, and a table changes only the properties it
sets. **A new name given as plain text is not a copy job:** a new copy job needs
`copy = true`.

### when the configuration is read

The library reads `types`, builds the schemas and sets the `dr` tag page when
it loads. It carries `-- priority: -10`
([load order](https://silverbullet.md/Space%20Lua)), so it loads after every
script without a priority, whatever page your `config.set` is on. A
`config.set` with a priority below -10 comes too late. After a change to
`CONFIG` run `System: Reload`, then `Space: Reindex`.

## Usage

### what pages call

| Call | Where |
| --- | --- |
| `${ITAM.views.page(_CTX.currentPage.name)}` | the last line of every object page: the view for its kind |
| `${ITAM.views.index("host")}` | the index page next to each kind's folder (`host`, `service`, `storage`, `network`, `policy`, `job`, `dr`) |
| `${ITAM.views.copies()}` | the policy index: copies and offsite copies of every protected storage |
| `${ITAM.views.architecture()}` | the entry page: hosts by site, with their networks |
| `${ITAM.views.types()}` | any page: the allowed `type` values of every kind in this space, as a table, so a page need not copy them |
| `${ITAM.views.types("host")}` | any page: the allowed `type` values of one kind (`host`, `service`, `network`, `storage`, `policy`, `job`) as an inline list, in the configured order |
| `${ITAM.views.decisions { area = "…", statuses = { "…" }, relations = { "dependsOn", "related", "supersedes" } }}` | a decision index: the decisions as a graph; every option is optional; `area` keeps the decisions of that area, also those that list it among several |
| `${ITAM.views.drDueForReview(180)}` | a decision index: active decisions not reviewed for that many days (default: `reviewDays`) |
| `${ITAM.views.drProvisional()}` | a decision index: the provisional decisions, longest unchanged first |

A page calls `ITAM.views.*` only. The rest of the `ITAM` namespace
(configuration, lists, helpers, schemas) and `ITAM.backup` (the chain) are the
library's own; a space that restricts what pages may call (an allowlist) needs
`ITAM.views.*` and nothing else.

### the views

| Kind | Sections |
| --- | --- |
| host | Services, Storage, Jobs, Networks: what it offers, holds, runs, connects to |
| service | Exposes (services whose `exposedVia` is this page), Logs in (`authVia`), Used by (`dependsOn`) |
| storage | Stack (the layers below and above, along `on`), Backup chain (with copies and offsite count), Backup diagram |
| network | Diagram, Members (hosts first); on a LAN also Addresses (every `lanIp` on it, macvlan containers of its hosts included) |
| policy | Storage under the policy (with copies and offsite count), Jobs implementing it |
| job | Copies (source to target) |
| decision (`dr`) | Governs (objects whose `decision` is this page) |

Every section is always shown; an empty one says *none*. Lists are sorted by
`type`, in the order of the type list, then by name. Tables are built as
Markdown; a view with a diagram converts its tables to HTML and joins
everything into one block, each section and diagram in its own `div`.

### the rules the schemas enforce

* A host needs a `location` unless its type is `external`; an `unused`
  reservation needs `lanIp`; every other host needs a `role`.
* Storage that is part of no host needs a `location`.
* A job type with `copy` needs a `source`, and a `target` too unless it has
  `inPlace`. An `inPlace` job keeps its copy on the same storage, whatever else
  is listed as target.
* A `location` must be one of `sites`, and an `area`, or each value of a list
  of areas, one of `dr.areas`, when those lists are configured.
* `type` and `auth` must be in the list of their kind. A service's `type` may
  be a list when it runs differently per host.
* A `domain` is an extra tag on a service of type `external`: `registered`
  and `renewal` are dates (`YYYY-MM-DD`), `mail` says who handles mail for it.

### building blocks

Usable on their own in Space Lua: `ITAM.views.linkedTo(tag, field, page)` (pages
whose `field` points to `page`), `ITAM.views.network(name)` (a network and
everything on it), `ITAM.views.stack(name)` (the storage layers around a storage;
`nil` when it stands alone), `ITAM.backup.chain(name)`, `ITAM.backup.summary(name)`,
`ITAM.backup.diagram(name)`, and the helpers in `ITAM` (`ITAM.list`, `ITAM.link`,
`ITAM.unlink`, `ITAM.short`, `ITAM.pages(tag)`, `ITAM.page(name)`,
`ITAM.byName(tag)`, `ITAM.copies(job)`, `ITAM.typesOf(kind)`,
`ITAM.definitionOf(kind, name)`, `ITAM.flowchart()`).

### commands

Each page template adds one command that creates a page of its kind:

* `ITAM: New Host`
* `ITAM: New Service`
* `ITAM: New Storage`
* `ITAM: New Network`
* `ITAM: New Policy`
* `ITAM: New Job`
* `ITAM: New Decision`

### page templates

The templates are installed next to this page, under `ITAM/Templates/`, and read
`pagePrefix`, `sites`, `dr.areas`, `dr.deciders`, `dr.owner` and the type
lists from the configuration, so a new page proposes the right folder and
lists the allowed values as comments.

### notes

* The diagrams use `mermaid.diagram` and `mermaid.relationGraph` of the
  Mermaid library: install `Mermaid` from the SilverBulletMD repository.
  Without it the views with a diagram fail.
* `relationGraph` shows at most 60 nodes by default; the backup, stack,
  architecture and decision diagrams build their own flowcharts and have no
  such cap.
* A replica (one storage kept in sync on several hosts) lists its hosts in
  `partOf` and the layer under each copy in `on`; the summary counts one copy
  per host. The same software on several hosts is one service.
* Not tested with Silverbullet+

## Code
