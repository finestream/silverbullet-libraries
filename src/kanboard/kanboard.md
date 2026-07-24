
# Kanboard

Synchronize tasks between Silverbullet and Kanboard while keeping
SilverBullet as the primary workspace for thinking and Kanboard as the
primary space for task management.

Enable minimal offline operations by leveraging native SilverBullet 
capabilities.

## Features & workflow

Consolidate your tasks in Kanboard and see them seamlessly as Silverbullet Tasks

- (optional) Capture ideas with `/newidea`
- (optional) Mull over your ideas with standard Silverbullet tools (see [Outlines](https://silverbullet.md/Outlines))
- (optional) Refile ideas into projects with the command "Kanboard: refile Project"
- create Silverbullet tasks anywhere you like (e.g., in a Project page)
- Send SilverBullet tasks to Kanboard with the command "Kanboard: Send Task" (or by using the shortcut) 

Here is where the magic happens: 
- the Plug creates a task in Kanboard
- it caches a copy of the task locally
- it replaces the original task with a live query to the Cache in SB
- Kanboard tasks are back-linked to the originating page

From now on 
- you manage your tasks in Kanboard
- you can sync them to silverbullet with the command "Kanboard: update Cache"
- each task in Kanboard links (with Permalinks) back to the page where it was created 

## Configuration

Add the following section to your `CONFIG` page in a space-lua block:

```
config.set {
  kanboard = {
      kbBaseUrl = "https://kanboard.mydomain.com", --Kanboard base URL
      sbBaseUrl = "https://silverbullet.mydomain.com", --Silverbullet base URL
      kbUsername = "me@mydomain.com", --Kanboard username
      kbToken = "5ec7e7", --Kanboard token for kbUsername obtain in Kanboard
      kbProjectId = 1, --default projectId in Kanboard 
      sbCachePath = "Kanboard", --Path on Silverbullet space where the tasks will be cached
      sbCacheRefreshHours = 6, --max cache age in hours
  }
}
```

## Usage

### slashcommands
`/newidea` creates a new idea in the current document (e.g., ideas.md)

### commands
`Kanboard: Refile Project` Creates a new project from the current idea
`Kanboard: Send Task` Sends a Silverbullet task to Kanboard 
`Kanboard: Update Cache` Updates the cache of Kanboard Tasks in Silverbullet

### virtual pages
`pageId:<pageId of the page>` Used to create permanent links to the orginating pages 
that survive page renaming 

## Code