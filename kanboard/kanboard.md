---
author: finestream
description: Integration between SilverBullet and Kanboard.
pageDecoration.prefix: "📝 "
name: "Library/Finestream/Kanboard"
tags: meta/library
---

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

Add the following section to your `CONFIG` page.

```
config.set {
  kanboard = {
      kbBaseUrl = "https://kanboard.mydomain.com", --Kanboard base URL
      sbBaseUrl = "https://silverbullet.mydomain.com", --Silverbullet base URL
      kbUsername = "me@mydomain.com", --Kanboard username
      kbToken = "5ec7e7", --Kanboard token for kbUsername
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

```space-lua
-----------------------------------------------------------------------
-- Package
-----------------------------------------------------------------------
library = {}

-----------------------------------------------------------------------
-- generateUuid()
--
-- Generates a random RFC4122 version-4 UUID, random variant (8,9,A,B)
--
-- The UUID is suitable for identifying SilverBullet pages and other
-- long-lived objects.
--
-- Returns:
--   String containing a UUID, for example:
--
--     550e8400-e29b-41d4-a716-446655440000
-----------------------------------------------------------------------
function library.generateUuid()
  return ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end)
end

-----------------------------------------------------------------------
-- escapePattern()
--
-- Escape regex special characters 
-----------------------------------------------------------------------
function library.escapePattern(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-----------------------------------------------------------------------
-- createPageWithText(page, text)
--
-- Creates a new page containing the supplied text.
--
-- Safety checks:
--   - page name must not be empty
--   - page must not already exist
--
-- Returns:
--   true
--       page successfully created
--
--   false, <message>
--       creation failed; message suitable for display to the user
--
-- This helper centralises page creation so every command behaves
-- consistently.
-----------------------------------------------------------------------
function library.createPageWithText(page, text)
    if page == nil or page == "" then
        return false, "No page name specified."
    end

    if space.pageExists(page) then
        return false, "Page already exists."
    end

    space.writePage(page, text)
    return true
end

-----------------------------------------------------------------------
-- setFrontmatter(key, value, force)
--
-- Sets a frontmatter property on the current page.
--
-- Behaviour:
--   - Creates frontmatter if none exists.
--   - Adds the key if it does not exist.
--   - If the key exists:
--       - force = true  -> overwrite value
--       - force = false -> return existing value
--
-- Returns:
--   true, value
--       Value successfully written.
--
--   false, existingValue
--       Key already exists and force = false.
-----------------------------------------------------------------------
function library.setFrontmatter(key, value, force)
    local text = editor.getText()

    -- Existing frontmatter?
    local fmStart, fmEnd, frontmatter = text:find("^(%-%-%-\n(.-)\n%-%-%-\n?)")

    if frontmatter then
        -- Key already exists?
        local patternKey = library.escapePattern(key)
        local existing = frontmatter:match(patternKey .. ":%s*([^\n]+)")

        if existing then
            if not force then
                return false, existing
            end

            frontmatter = frontmatter:gsub(
                "\n" .. key .. ":%s*.-\n",
                "\n" .. key .. ": " .. tostring(value) .. "\n",
                1
            )
        else
            frontmatter = frontmatter:gsub(
                "\n%-%-%-\n?$",
                "\n" .. key .. ": " .. tostring(value) .. "\n---\n"
            )
        end

        editor.setText(frontmatter .. text:sub(fmEnd + 1))
        return true, value
    end

    -- No frontmatter: create one
    local newFrontmatter =
        "---\n" ..
        key .. ": " .. tostring(value) .. "\n" ..
        "---\n\n"

    editor.setText(newFrontmatter .. text)
    return true, value
end

-----------------------------------------------------------------------
-- Package
-----------------------------------------------------------------------
org = {}

-----------------------------------------------------------------------
-- currentSubtree()
--
-- Returns the complete subtree surrounding the current cursor.
--
-- A subtree is defined as:
--   - a level-2 heading ("## ")
--   - all following text
--   - until the next level-2 heading or the end of the document.
--
-- Level-3 headings and below ("###", "####", ...) are considered part
-- of the subtree and do not terminate it.
--
-- Returns:
--   {
--     start  = first character of the heading
--     finish = first character after the subtree
--     text   = subtree text
--   }
--
-- Returns nil if no enclosing subtree exists.
--
-- This function is the foundation for commands such as:
--   - refile
--   - archive
--   - duplicate
--   - extract
-----------------------------------------------------------------------
function org.currentSubtree()
  local text = editor.getText()
  local cursor = editor.getCursor()

  local start = 1

  -- First heading in file?
  if not text:match("^## ") then
    start = text:find("\n## ", 1, true)
    if not start then
      return nil -- no level-2 headings found
    end
    start = start + 1 -- skip the newline
  end

  local finish = text:find("\n## ", start + 1, true)

  while finish do
    if cursor >= start and cursor < finish then
      return {
        start = start,
        finish = finish,
        text = text:sub(start, finish - 1)
      }
    end

    start = finish + 1
    finish = text:find("\n## ", start + 1, true)
  end

  -- Last subtree extends to end of file
  if cursor >= start then
    return {
      start = start,
      finish = #text + 1,
      text = text:sub(start)
    }
  end

  return nil
end

-----------------------------------------------------------------------
-- currentTask()
--
-- Returns the task surrounding the current cursor.
--
-- A task is a single line containing:
--
--   - [ ]
--   * [ ]
--   - [X]
--   * [TODO]
--
-- Returns:
--   {
--     start  = first character of the task
--     finish = first character after the task
--     status = task status
--     text   = task text
--   }
--
-- Returns nil if the cursor is not inside exactly one task.
-----------------------------------------------------------------------
function org.currentTask()
    local cursor = editor.getCursor()
    local currpage = editor.getCurrentPage()

    local tasks = query[[
        from index.tasks()
        where page == currpage
            and pos <= cursor
            and toPos >= cursor
    ]]

    if #tasks ~= 1 then
        editor.flashNotification(
            "Expected exactly one task, found " .. #tasks .. ".",
            "error"
        )
        -- return nil
    end

    local task = tasks[1]

    return {
        start = task.pos,
        finish = task.toPos,
        status = task.state,
        text = task.name
    }
end

-----------------------------------------------------------------------
-- Package
-----------------------------------------------------------------------
kanboard = {}

-----------------------------------------------------------------------
-- taskToMarkdown(task)
--
-- Converts a Kanboard task into a SilverBullet task.
--
-- Expected task fields:
--   id
--   title
--   status      (" ", "X", or custom status)
--   link        (Permanent Kanboard link)
--
-- Returns:
--   Markdown task as a single line.
-----------------------------------------------------------------------
function kanboard.taskToMarkdown(task)
    local status = " "

    if task.is_active == "0" then
        status = "closed"
    else
        status = "open"
    end

    return string.format(
        "${query[[from index.tasks() where kbId == %s select templates.taskItem(_)]]}",
        task.id
    )
end

-----------------------------------------------------------------------
-- rpc(method, params)
--
-- Executes a JSON-RPC request against Kanboard.
--
-- Returns:
--   result
--
-- Raises an error if the RPC call fails.
-----------------------------------------------------------------------
function kanboard.rpc(method, params)
    local cfg = config.get("kanboard") 
    local response = net.proxyFetch(cfg.url, {
        method = "POST",
        headers = {
            Authorization = "Basic " .. encoding.base64Encode(cfg.username .. ":" .. cfg.token)
        },
        body = {
            jsonrpc = "2.0",
            id = 1,
            method = method,
            params = params
        }
    })
    return response
end

-----------------------------------------------------------------------
-- checkResponse(response)
--
-- Checks the result of a Kanboard RPC call.
--
-- Returns:
--   true  if no error occurred
--   false otherwise
--
-- In case of failure an error notification is shown.
-----------------------------------------------------------------------
function kanboard.checkResponse(response)
    return response.ok
end

-----------------------------------------------------------------------
-- replaceCurrentTask(task, kbTask)
--
-- Replaces a SilverBullet task with its Kanboard representation.
--
-- Parameters:
--   task
--       Result returned by org.currentTask().
--
--   kbTask
--       Task returned by Kanboard getTask().
-----------------------------------------------------------------------
function kanboard.replaceCurrentTask(task, kbTask)
    editor.replaceRange(
        task.start,
        task.finish,
        kanboard.taskToMarkdown(kbTask)
    )
end

-----------------------------------------------------------------------
-- sendTask()
--
-- Sends the current SilverBullet task to Kanboard.
--
-- Workflow:
--   1. Read the current task.
--   2. Get a pageId for the current page.
--   3. Create the task in Kanboard.
--   4. Close the task if required.
--   5. Update the KB task with a permanent link to the SB page.
--   6. Retrieve the task (to obtain its permanent URL).
--   7. Replace the original task with a linked task.
--   8. Persist the pageId in the page frontmatter.
--   9. Add the task to the local cache.
-----------------------------------------------------------------------
function kanboard.sendTask(projectId)

    projectId = projectId or config.get("kanboard").projectId
  
    -- 1. Read the current task.
    local task = org.currentTask()
    if not task then
        editor.flashNotification("No task found.", "error")
        return
    end
  
    -- 2. Get a pageId for the current page.
    local pageId = editor.getCurrentPageMeta().pageId
    if pageId == nil or pageId == "" then
        pageId = library.generateUuid()
    end
  
  
    -- 3. Create the task in Kanboard.
    local response = kanboard.rpc("createTask", {
        title = task.text,
        description = "Task Status in SB at creation: [" .. task.status .. "]",
        reference = pageId, -- not sure if it works
        project_id = projectId
    })

    local taskId
    if kanboard.checkResponse(response) then
        taskId = response.body.result
    else
        editor.flashNotification("Unable to create Kanboard task.", "error")
        return
    end

    -- 4. Close the task if required.
    if task.status == "x" or task.status == "X" then
        response = kanboard.rpc("closeTask", {
            task_id = taskId
        })

        if not kanboard.checkResponse(response) then
            editor.flashNotification("Unable to close Kanboard task.", "error")
            return
        end
    end

    -- 5. Update the KB task with a permanent link to the SB page.
    response = kanboard.rpc("createExternalTaskLink", {
        task_id = taskId,
        url = config.get("kanboard").sbBaseUrl .. "/pageId:" .. pageId,
        dependency = "related",
        type = "weblink",
        title = "SB Context"
    })

    if not kanboard.checkResponse(response) then
        editor.flashNotification("Unable to link Kanboard task to SilverBullet.", "error")
        return
    end

    -- 6. Retrieve the task (to obtain its permanent URL).
    response = kanboard.rpc("getTask", {
        task_id = taskId
    })

    local kbTask
    if kanboard.checkResponse(response) then
        kbTask = response.body.result
    else
        editor.flashNotification("Unable to retrieve Kanboard task.", "error")
        return
    end

    -- 7. Replace the original task with a linked task.
    kanboard.replaceCurrentTask(task, kbTask)

    -- 8. Persist the pageId in the page frontmatter.
    library.setFrontmatter("pageId", pageId, false)

    -- 9. Add the task to the local cache.
    kanboard.updateCache(projectId, kbTask)

    editor.flashNotification("Task sent to Kanboard.")
end

-----------------------------------------------------------------------
-- updateCache(projectId, kbTask)
--
-- Updates the local cache.
--
-- If kbTask is nil, the cache does not exist, or the cache is stale,
-- the cache is rebuilt from Kanboard.
--
-- Otherwise only the supplied task is updated.
--
-- This dual implementation is intentional. A full rebuild delegates
-- the iteration over all tasks to Kanboard (getAllTasks), avoiding one
-- RPC per task. Incremental updates are optimized for the common case
-- where only one task has changed.
-----------------------------------------------------------------------
function kanboard.updateCache(projectId, kbTask)

    projectId = projectId or config.get("kanboard").projectId

    -- Retrieve project.
    local response = kanboard.rpc("getProjectById", {
        project_id = projectId
    })

    local project
    if kanboard.checkResponse(response) then
        project = response.body.result
    else
        editor.flashNotification("Unable to retrieve project.", "error")
        return
    end

    -- Retrieve columns names.
    response = kanboard.rpc("getColumns", {
        project_id = projectId
    })

    local columns
    if kanboard.checkResponse(response) then
        columns = {}
        for _, column in ipairs(response.body.result) do
            columns[column.id] = column.title
        end
    else
        editor.flashNotification("Unable to retrieve columns.", "error")
        return
    end

    -- Retrieve categories names.
    response = kanboard.rpc("getAllCategories", {
        project_id = projectId
    })

    local categories
    if kanboard.checkResponse(response) then
        categories = {}
        for _, category in ipairs(response.body.result) do
            categories[category.id] = category.name
        end
    else
        editor.flashNotification("Unable to retrieve categories.", "error")
        return
    end

    -- Decide between full rebuild and incremental update.
    local cachePage = config.get("kanboard").cachePath .. "/" .. project.name
    local cacheMeta = query[[from index.subPages(config.get("kanboard").cachePath) where projectId == projectId]]

    if (cacheMeta == nil) or (kbTask == nil) then
        kanboard.rebuildCache(project, cachePage, columns, categories)
        return
    else
        local age = os.time() - (tonumber(cacheMeta[1].lastSync) or 0)
        if (config.get("kanboard").debug) then
              editor.flashNotification("Kanboarddebug: cache Age =" .. age .. " now =" .. os.time() .. " lastSync =" .. cacheMeta[1].lastSync)
        end
        if age > config.get("kanboard").cacheRefreshHours * 3600 then
            kanboard.rebuildCache(project, cachePage, columns, categories)
            return
        end
    end

    kanboard.updateCacheEntry(
        kbTask,
        cachePage,
        columns,
        categories
    )
end


-----------------------------------------------------------------------
-- rebuildCache(project, cachePage, columns, categories)
--
-- Rebuilds a project's cache from Kanboard.
-----------------------------------------------------------------------
function kanboard.rebuildCache(project, cachePage, columns, categories)

    editor.flashNotification(project.name)

    -- Retrieve all tasks.
    local response = kanboard.rpc("getAllTasks", {
        project_id = project.id
    })

    local tasks
    if kanboard.checkResponse(response) then
        tasks = response.body.result
    else
        editor.flashNotification("Unable to retrieve tasks.", "error")
        return
    end

    -- Build page.
    local page = {}

    table.insert(page, "---")
    table.insert(page, "pageId: " .. library.generateUuid())
    table.insert(page, "projectId: " .. project.id)
    table.insert(page, "lastSync: " .. os.time())
    table.insert(page, "---")
    table.insert(page, "")
    table.insert(page, "[Kanban board](" .. project.url.board .. ")")
    table.insert(page, "")

    for _, task in ipairs(tasks) do

        local entry = kanboard.buildCacheEntry(
            task,
            columns,
            categories
        )

        if not entry then
            return
        end

        table.insert(page, entry)
        table.insert(page, "")
    end

    space.writePage(
        cachePage,
        table.concat(page, "\n")
    )

    editor.flashNotification(
        "Kanboard: Cache project " .. project.id .. " " .. project.name .. " rebuilt (" .. #tasks .. " tasks)."
    )
end

-----------------------------------------------------------------------
-- updateCacheEntry(kbTask, cachePage, columns, categories)
--
-- Updates or appends a single cache entry.
-----------------------------------------------------------------------
function kanboard.updateCacheEntry(kbTask, cachePage, columns, categories)

    local entry = kanboard.buildCacheEntry(
        kbTask,
        columns,
        categories
    )

    if not entry then
        return
    end
    editor.flashNotification(entry)

    -------------------------------------------------------------------
    -- Locate the cached task.
    --
    -- TODO:
    -- Replace the query below with the final SilverBullet query once
    -- validated. The query should return at most one task together with
    -- its pos/toPos.
    -------------------------------------------------------------------
    local tasks = query[[
        from index.tag "task"
        where page == cachePage
          and kbId == tostring(kbTask.id)
    ]]

    local text = space.readPage(cachePage)

    if #tasks == 0 then
        text = text .. "\n" .. entry .. "\n"

    elseif #tasks == 1 then

        -- Replace.
        local task = tasks[1]

        text =
            text:sub(1, task.pos - 1)
            .. entry
            .. text:sub(task.toPos + 1)

    else
        editor.flashNotification(
            "Cache contains duplicate kbId - perform a full update" .. kbTask.id,
            "error"
        )
        return
    end

    space.writePage(cachePage, text)

    editor.flashNotification("Cache updated.")
end


-----------------------------------------------------------------------
-- buildCacheEntry(task, columns, categories)
--
-- Builds the canonical representation of a Kanboard task in the local
-- cache.
--
-- This is the single point of maintenance for the cache format.
-----------------------------------------------------------------------
function kanboard.buildCacheEntry(task, columns, categories)

    -- Retrieve tags.
    local response = kanboard.rpc("getTaskTags", {
        task_id = task.id
    })

    local tags
    if kanboard.checkResponse(response) then
        tags = response.body.result
    else
        editor.flashNotification(
            "Unable to retrieve task tags.",
            "error"
        )
        return nil
    end

    -- Build status.
    local status = " "

    if task.is_active == "0" then
        status = "x"
    end

    -- Build tags.
    local tagList = {}

    if task.category_id ~= "0" then
        local category = categories[task.category_id]

        if category then
            category = category:gsub("[<>]", "")
            table.insert(tagList, "#<" .. category .. ">")
        end
    end

    for _, tag in pairs(tags) do
        tag = tag:gsub("[<>]", "")
        table.insert(tagList, "#<" .. tag .. ">")
    end

    -- Build attributes.
    local attributes = {}

    table.insert(attributes, "[kbId: " .. task.id .. "]")

    if columns[task.column_id] then
        table.insert(
            attributes,
            "[column: " .. columns[task.column_id] .. "]"
        )
    end

    if task.project_id ~= "0" then
        table.insert(
            attributes,
            "[projectId: " .. task.project_id .. "]"
        )
    end

    if task.date_due ~= "0" then
        table.insert(
            attributes,
            "[due: "
                .. os.date("%Y-%m-%d", tonumber(task.date_due))
                .. "]"
        )
    end

    if task.score ~= "0" then
        table.insert(
            attributes,
            "[priority: " .. task.score .. "]"
        )
    end

    if task.position ~= "0" then
        table.insert(
            attributes,
            "[position: " .. task.position .. "]"
        )
    end

    if task.swimlane_id ~= "0" then
        table.insert(
            attributes,
            "[swimlaneId: " .. task.swimlane_id .. "]"
        )
    end

    if task.recurrence_status ~= "0" then
        table.insert(
            attributes,
            "[recurrence: " .. task.recurrence_status .. "]"
        )
    end

    if task.reference ~= "" then
        table.insert(
            attributes,
            "[pageId: " .. task.reference .. "]"
        )
    end

    return string.format(
        "* [%s] %s ([KB](%s)) %s %s",
        status,
        task.title,
        task.url,
        table.concat(tagList, " "),
        table.concat(attributes, " ")
    )
end

-----------------------------------------------------------------------
-- Command:refileSubtree
--
-- Moves the current subtree into its own page.
--
-- Current implementation (safe mode):
--
--   1. Determine the subtree surrounding the cursor.
--   2. Prompt for a destination page.
--   3. Create the destination page.
--   4. Insert a backlink ("Moved to: [[Page]]") below the heading.
--
-- The original subtree is intentionally left untouched while the command
-- is being tested.
--
-- Planned final behaviour:
--
--   5. Remove the original subtree after successful page creation,
--      leaving only the backlink in the source document.
-----------------------------------------------------------------------
command.define {
  name = "refileSubtree",
  run = function()
    local subtree = org.currentSubtree()
    if not subtree then
      editor.flashNotification("No subtree found.", "error")
      return
    end

    local page = editor.prompt(
      "Move subtree to page:",
      "Project/New project " .. os.date("%Y-%m-%d")
    )

    local ok, err = library.createPageWithText(page, subtree.text)
    if not ok then
      editor.flashNotification(err, "error")
      return
    end

    local text = editor.getText()
    local _, headingEnd = text:find("\n", subtree.start, true)
    if not headingEnd then
      headingEnd = #text
    end

    editor.replaceRange(
      headingEnd - 1,
      subtree.finish - 1,
      "\nMoved to: [[" .. page .. "]]"
    )

    editor.flashNotification("Subtree copied to '" .. page .. "'.")
  end
}

-----------------------------------------------------------------------
-- slashcommand:idea
--
-- Slash command used to capture a new idea with minimal friction.
--
-- Inserts a new level-2 heading at the current cursor position together
-- with a creation timestamp. The cursor is positioned on the heading so
-- the user can immediately type the title.
--
-- Intended workflow:
--   /idea
--   -> type title
--   -> continue writing below
-----------------------------------------------------------------------
slashCommand.define {
  name = "Idea: New",
  run = function()
    text = string.format("## |^|\n[created: %s]",os.date("%Y-%m-%d %H:%M"))
    editor.insertAtCursor(text, false, true)
  end
}

-----------------------------------------------------------------------
-- Command: add page id
-----------------------------------------------------------------------
command.define {
    name = "Page: Add id",
    run = function()
        local uuid = library.generateUuid()
        local ok, value = library.setFrontmatter("pageId", uuid, false)

        if ok then
            editor.flashNotification("pageId = " .. value)
        else
            editor.flashNotification("Existing pageId = " .. value)
        end
    end
}

-----------------------------------------------------------------------
-- Send current task to Kanboard.
-----------------------------------------------------------------------
command.define {
    name = "kanboard: Send Task",
    mac = "Ctrl-Cmd-a",
    key = "Ctrl-Alt-a",
    run = function()

        local projectId = editor.getCurrentPageMeta().kbProject
        kanboard.sendTask(projectId)

    end
}

-----------------------------------------------------------------------
-- Rebuild the Kanboard cache.
-----------------------------------------------------------------------
command.define {
    name = "kanboard: Update Cache",
    run = function()

        local projectId = editor.getCurrentPageMeta().kbProject
        kanboard.updateCache(projectId)

    end
}

-----------------------------------------------------------------------
-- Get page by pageId
-----------------------------------------------------------------------
virtualPage.define {
    pattern = "pageId:(.+)",
    run = function(tgtpageId)

        local pages = query[[
            from index.pages()
            where pageId == tgtpageId
        ]]

        if #pages == 0 then
            return "# Page not found\n\nNo page with pageId `" .. pageId .. "`."
        end

        if #pages > 1 then
            return "# Duplicate pageId\n\nMore than one page has pageId `" .. pageId .. "`.\n"
        end

        return "# Page with PageId " .. tgtpageId .. "\n\n[[" .. pages[1].name .. "]]"
    end
}
```