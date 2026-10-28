
# Kanboard

Synchronize tasks between Silverbullet and Kanboard while keeping SilverBullet as the primary workspace for thinking and Kanboard as the primary space for task management.

It enables minimal offline operations by leveraging native SilverBullet capabilities.

## Features

* *Synchronise and offline use* all open Kanboard Task to Silverbullet. The Kanboard Tasks are stored in a Silverbullet page for each Kanboard project. Most Kanborad Metadata is available in Silverbullet.
* *Native Silverbullet tasks* Kanboard tasks are imported as native Silverbullets tasks. They can be queries as any other Kanboard ojbect and they are synched for offline use via Silverbullet PWA capabilities.
* *Create new tasks* new Kanboard tasks can be created directly in Kanban and moved to Kanboard. Moving a task does the following: 1) it creates a task in Kanboard with the relevant attributes 2) it adds the tasks to the cache and 3) it replaces the task with a query. Tasks stay linked to pages even if pages are renamed or moved around.
* *Close tasks* Tasks can be closed by using the native Silverbullet approach. Closed tasks can be synched back to Kanboard by usind the relevant command. Please note that Kanboard colums are not stored as states but as column attributes and you can configure if closing a task moves the task to the last column in Kanboard and/or closes it.
* *Convenience* a number of slashcommands are defined to insert pre-defined queries and attributes to the tasks.

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

### virtual pages

`pageId:<pageId of the page>` Used to create permanent links to the orginating pages
that survive page renaming

### notes

* The library only caches Kanboard tasks that are not closed.
* The library only caches active projects. When a project is closed or deleted in Kanboard, its cache page `<sbCachePath>/<projectId>` is deleted on the next cache update.
* The library works with <https://github.com/Mr-xRed/silverbullet-libraries/blob/main/TaskManager.md>
* Not tested with Silverbullet+

## Code
