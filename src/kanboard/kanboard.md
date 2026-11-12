
# Kanboard

Synchronize tasks between Silverbullet and Kanboard while keeping SilverBullet as the primary workspace for thinking and Kanboard as the primary space for task management.

It enables minimal offline operations by leveraging native SilverBullet capabilities.

## Features

* *Synchronise and offline use* all open Kanboard Task to Silverbullet. The Kanboard Tasks are stored in a Silverbullet page for each Kanboard project. Most Kanborad Metadata is available in Silverbullet.
* *Native Silverbullet tasks* Kanboard tasks are imported as native Silverbullets tasks. They can be queries as any other Kanboard ojbect and they are synched for offline use via Silverbullet PWA capabilities.
* *Create new tasks* new Kanboard tasks can be created directly in Kanban and moved to Kanboard. Moving a task does the following: 1) it creates a task in Kanboard with the relevant attributes 2) it adds the tasks to the cache and 3) it replaces the task with a query. Tasks stay linked to pages even if pages are renamed or moved around.
* *Close tasks* Tasks can be closed by using the native Silverbullet approach. Closed tasks can be synched back to Kanboard by usind the relevant command. Please note that Kanboard colums are not stored as states but as column attributes and you can configure if closing a task moves the task to the last column in Kanboard and/or closes it.
* *Convenience* a number of slashcommands are defined to insert pre-defined queries and attributes to the tasks.
* *Task table* any query over tasks can be shown as a table with a button to mark a task done, sorting, filters and a search field: `Kanboard.views.tasks`.
* *Task link* `Kanboard.views.taskLink(id)` links a task by its number: `[757](https://<kbBaseUrl>/task/757)`.

##  Suggested workflow

The library tries to stay true to Silverbullet and provides one more tool in your toolbox while not enforcing a particular workflow. Here is mine as inspirat

* (optional) Capture ideas with `/newidea`
* (optional) Mull over your ideas with standard Silverbullet tools (see [Outlines](https://silverbullet.md/Outlines))
* (optional) Refile ideas into projects with the command "Kanboard: refile Project"
* Create Silverbullet tasks anywhere you like (e.g., in a Project page)
* Add attributes as needed
* Send SilverBullet tasks to Kanboard with the command "Kanboard: Send Task" (or by using the shortcut)

Here is where the magic happens:

* the Plug creates a task in Kanboard
* it caches a copy of the task locally
* it replaces the original task with a live query to the Cache in SB
* Kanboard tasks are back-linked to the originating page

From now on

* you manage your tasks in Kanboard
* you can sync them to silverbullet with the command "Kanboard: update Cache"
* each task in Kanboard links (with Permalinks) back to the page where it was created

## Configuration

Add the following section to your `CONFIG` page in a space-lua block:

```lua
config.set {
  kanboard = {
      kbBaseUrl = "https://kanboard.mydomain.com", --Kanboard base URL
      sbBaseUrl = "https://silverbullet.mydomain.com", --Silverbullet base URL
      kbUsername = "me@mydomain.com", --Kanboard username
      kbToken = "5ec7e7", --Kanboard token for kbUsername obtain in Kanboard
      kbProjectId = 1, --default projectId in Kanboard 
      kbMoveDone = true, -- options move tasks done in SB to the last Kanboard column when syncing status
      kbCloseDone = true, -- options mark tasks done in SB as closed in Kanboard when syncing status
      sbCachePath = "Kanboard", --Path on Silverbullet space where the tasks will be cached
      sbCacheRefreshHours = 6, --max cache age in hours
      verbosity = 1, -- optional: which notifications to show, see below
      taskTable = { -- optional: the task table, see below
          open = "⭕️", done = "🟢", boxSize = "1.8em", emptyAttribute = "🚫",
      },
  }
}
```

`verbosity` sets which notifications the library shows:

| Level | Shows |
|---|---|
| `0` | nothing at all |
| `1` | errors (default) |
| `2` | errors and warnings, e.g. a task marked done in SB that no longer exists in Kanboard |
| `3` | all of the above, and information when things went fine, e.g. "Task sent to Kanboard." or "Updated cache for 2 project(s)." |
| `4` | all of the above, and debugging information, e.g. every HTTP response and the cache age |

A value below 0 or above 4 is treated as 0 or 4. The older `debug = true` still works and means `verbosity = 4` when `verbosity` is not set.

## Usage

### slashcommands

`/idea` creates a new idea in the current document (e.g., ideas.md)
`/getTasks` inserts a query showing all tasks created from this page
`/getTasksByProjectId`inserts a query showing all tasks of a given project

### commands

`Kanboard: Refile Project` Creates a new project from the current idea
`Kanboard: Send Task` Sends a Silverbullet task to Kanboard
`Kanboard: Update Cache` Updates tasks marked as done in SB on Kanboard, refreshes all caches in Silverbullet and deletes the caches of projects that are closed or deleted in Kanboard (or that you are no longer a member of)

### task table

`Kanboard.views.tasks(rows, columns)` shows tasks as a table. `rows` is a query over tasks, `columns` an optional list of attribute columns:

```lua
${Kanboard.views.tasks(query[[from t = index.tasks() where t.column == "Ready" order by t.due]])}

${Kanboard.views.tasks(query[[from t = index.tasks() where t.category == "Work"]], {
  {"Due", "due", "DD.MM.YY"},
  {"Column", "column"},
})}
```

Every row has a button showing whether the task is open or done, the task text with its links, the page, and one cell per attribute column.

* *The button* marks the task done, or open again, where it is written, as ticking it in the editor does. A task of the Kanboard cache marked done reaches Kanboard with the next `Kanboard: Update Cache`, as configured with `kbCloseDone` and `kbMoveDone`.
* *Page* is the page a task was sent to Kanboard from, and otherwise the page the task is written on.
* *Sort* with a click on a column name: ascending (▲), descending (▼), then back to the order of the query. Tasks without a value come last.
* *Filter* with the funnel beside a column name: it lists the values of that column, each with the number of tasks, to tick and untick.
* *Search* looks in all columns. Beside the search field are the number of tasks shown and a button that resets search, sorting and filters.

A column is `{header, attribute, format}`. `attribute` is the name of a task attribute (`[due: 2026-12-01]` is `due`; the Kanboard cache has `project`, `category`, `column`, `swimlane`, `due`, `priority`, `owner` and more). `format` is `"string"` (the default), `"date"` (`YYYY-MM-DD`), `"dateTime"` (`YYYY-MM-DD hh:mm`) or a pattern made of `YYYY`, `YY`, `MM`, `DD`, `hh` and `mm`. A date Kanboard does not have (the cache writes it as `1970-01-01`) is shown as empty.

Without `columns` the table shows the `defaultAttributes` of the configuration. The `taskTable` section of the configuration is optional as a whole; these are its defaults:

```lua
taskTable = {
    open = "☐",             -- text of the button of an open task
    done = "☑",             -- text of the button of a done task
    boxSize = "1.4em",      -- size of that button, a CSS length
    emptyAttribute = "---", -- shown for an attribute a task does not have
    defaultAttributes = {   -- the attribute columns when a page passes none
        {"Project", "project", "string"},
        {"Category", "category", "string"},
        {"Due Date", "due", "date"},
        {"Swimlane", "swimlane", "string"},
        {"Column", "column", "string"},
    },
}
```

Task texts, page names and attribute values are data to the table: it shows them as text, whatever they contain. In a task text `[[Page]]`, `[label](url)` and bare `http(s)` URLs become links; a `[label](url)` with another scheme stays text. The look is the style block below, which a `space-style` block of your own can override (class names start with `kanboard-tasks`).

### task link

`Kanboard.views.taskLink(id)` returns the markdown link of a Kanboard task, built from `kbBaseUrl`, so a page does not write the link format by hand:

```lua
${Kanboard.views.taskLink(757)}
```

shows as [757](https://kanban.example.org/task/757) when `kbBaseUrl` is `https://kanban.example.org`. `id` is a number or a string of digits. For anything else (zero, a negative or fractional number, text, nothing) and when `kbBaseUrl` is not configured the function returns nothing. The link text is the number with no `#`, which SilverBullet would read as a tag.

### virtual pages

`pageId:<pageId of the page>` Used to create permanent links to the orginating pages
that survive page renaming

### notes

* The library only caches Kanboard tasks that are not closed.
* The library only caches active projects. When a project is closed or deleted in Kanboard, its cache page `<sbCachePath>/<projectId>` is deleted on the next cache update.
* The library works with <https://github.com/Mr-xRed/silverbullet-libraries/blob/main/TaskManager.md>
* Not tested with Silverbullet+

## Style

```space-style
.kanboard-tasks {
  font-size: 0.8em;
}

.kanboard-tasks-toolbar,
.kanboard-tasks-panel {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.3em 0.8em;
  margin-bottom: 0.4em;
}

/* The right padding keeps the choices clear of SilverBullet's own widget
   buttons, which appear in the top right corner. */
.kanboard-tasks-panel {
  padding: 0.4em 7em 0.4em 0.8em;
  border: 1px solid var(--button-border-color);
  border-radius: 10px;
}

.kanboard-tasks-panel-title {
  font-weight: bold;
}

.kanboard-tasks-choice {
  white-space: nowrap;
  cursor: pointer;
}

.kanboard-tasks-search {
  flex: 0 1 18em;
  min-width: 8em;
  padding: 0.2em 0.8em;
  font: inherit;
  color: inherit;
  background: var(--text-field-background-color);
  border: 1px solid var(--button-border-color);
  border-radius: 1em;
}

.kanboard-tasks-count,
.kanboard-tasks-note {
  color: var(--subtle-color);
}

.kanboard-tasks button {
  font: inherit;
  cursor: pointer;
}

.kanboard-tasks-button {
  padding: 0.1em 0.8em;
  color: var(--button-color);
  background: var(--button-background-color);
  border: 1px solid var(--button-border-color);
  border-radius: 1em;
}

.kanboard-tasks-table {
  display: table;
  width: 100%;
  border-collapse: separate;
  border-spacing: 0 2px;
}

.kanboard-tasks-head {
  display: table-header-group;
}

.kanboard-tasks-body {
  display: table-row-group;
}

.kanboard-tasks-row {
  display: table-row;
}

/* Words are kept whole, except in the task text: a long word there (a URL)
   must not push the last columns out of view. */
.kanboard-tasks-cell {
  display: table-cell;
  padding: 2px 4px;
  text-align: center;
  vertical-align: middle;
  overflow-wrap: normal;
  word-break: normal;
}

.kanboard-tasks-cell.kanboard-tasks-task,
.kanboard-tasks-cell.kanboard-tasks-page {
  text-align: left;
}

.kanboard-tasks-cell.kanboard-tasks-task {
  min-width: 10em;
  overflow-wrap: anywhere;
}

.kanboard-tasks-cell.kanboard-tasks-state {
  width: 1%;
  white-space: nowrap;
}

.kanboard-tasks-cell.kanboard-tasks-date {
  white-space: nowrap;
}

.kanboard-tasks-head .kanboard-tasks-cell {
  padding-top: 5px;
  padding-bottom: 5px;
  color: var(--editor-table-head-color);
  background: var(--editor-table-head-background-color);
}

.kanboard-tasks-head .kanboard-tasks-cell:first-child {
  border-top-left-radius: 10px;
}

.kanboard-tasks-head .kanboard-tasks-cell:last-child {
  border-top-right-radius: 10px;
}

.kanboard-tasks-even .kanboard-tasks-cell {
  background: var(--editor-table-even-background-color);
}

.kanboard-tasks-sort,
.kanboard-tasks-filter,
.kanboard-tasks-toggle {
  padding: 0 2px;
  color: inherit;
  background: transparent;
  border: none;
}

/* The funnel stays beside the column name when the name wraps. */
.kanboard-tasks-heading {
  display: inline-flex;
  align-items: center;
}

.kanboard-tasks-sort {
  font-weight: bold;
  text-align: left;
}

.kanboard-tasks-mark:not(:empty) {
  margin-left: 0.3em;
}

.kanboard-tasks-filter {
  vertical-align: middle;
  opacity: 0.5;
}

.kanboard-tasks-filter:hover,
.kanboard-tasks-filter.kanboard-tasks-active {
  opacity: 1;
}

.kanboard-tasks-filter.kanboard-tasks-active svg {
  fill: currentColor;
}

.kanboard-tasks-toggle {
  line-height: 1;
}

.kanboard-tasks-toggle:disabled {
  cursor: default;
}

.kanboard-tasks-done .kanboard-tasks-task {
  text-decoration: line-through;
}

.kanboard-tasks-done .kanboard-tasks-task,
.kanboard-tasks-empty {
  color: var(--subtle-color);
}

.kanboard-tasks-link {
  padding: 0 4px;
  color: var(--editor-wiki-link-page-color);
  background: var(--editor-wiki-link-page-background-color);
  border-radius: 5px;
  text-decoration: none;
  cursor: pointer;
}
```

## Code
