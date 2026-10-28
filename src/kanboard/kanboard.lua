-----------------------------------------------------------------------
-- Package
-----------------------------------------------------------------------
Kanboard = {}

-----------------------------------------------------------------------
-- verbosity()
--
-- Reads the notification level from config.kanboard.verbosity:
--   0 silent, 1 errors (default), 2 + warnings, 3 + info, 4 + debug
-- (see Library.notify).
--
-- The older `debug = true` still works and means 4 when verbosity is not
-- set. A value below 0 or above 4 is clamped; anything that is not a
-- number falls back to the default.
--
-- Installed as Library.verbosity, so the Library's own notifications
-- follow the same setting.
-----------------------------------------------------------------------
function Kanboard.verbosity()
	local cfg = config.get("kanboard") or {}
	local level = tonumber(cfg.verbosity)
	if level == nil then
		if cfg.debug then
			return Library.DEBUG
		end
		return Library.ERROR
	end
	level = math.floor(level)
	if level < Library.SILENT then
		return Library.SILENT
	end
	if level > Library.DEBUG then
		return Library.DEBUG
	end
	return level
end
Library.verbosity = Kanboard.verbosity

-----------------------------------------------------------------------
-- queryTask(task)
--
-- Generates a query to find the reference in the cached tasks.
--
-- Expected task fields:
--   id
--
-- Returns:
--   Query returning the task
-----------------------------------------------------------------------
function Kanboard.queryTask(taskId)
	return string.format("${query[[from index.tasks() where kbId == %s select templates.taskItem(_)]]}", taskId)
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
function Kanboard.rpc(method, params)
	local cfg = config.get("kanboard")
	local rpcUrl = cfg.kbBaseUrl:gsub("/+$", "")
	if not rpcUrl:find("jsonrpc%.php$") then
		rpcUrl = rpcUrl .. "/jsonrpc.php"
	end
	local response = net.proxyFetch(rpcUrl, {
		method = "POST",
		headers = {
			Authorization = "Basic " .. encoding.base64Encode(cfg.kbUsername .. ":" .. cfg.kbToken)
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
-- The HTTP outcome is shown at verbosity 4 (debug); the caller reports
-- the failure itself.
-----------------------------------------------------------------------
function Kanboard.checkResponse(response)
	if response.ok then
		Library.notify(Library.DEBUG, "Kanboarddebug: HTTP Response OK")
	else
		Library.notify(Library.DEBUG, "Kanboarddebug: " .. tostring(response.status))
	end
	return response.ok
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
--   6. Replace the original task with a linked task.
--   7. Persist the pageId in the page frontmatter.
--   8. Add the task to the local cache.
-----------------------------------------------------------------------
function Kanboard.sendTask(projectId, swimlaneId)
	-- 1. Read the current task.
	local task = Library.currentTask()
	if not task then
		Library.notify(Library.DEBUG, "No task found.")
		return
	end

	-- 2. Get a pageId for the current page.
	local pageId = editor.getCurrentPageMeta().pageId
	if pageId == nil or pageId == "" then
		pageId = Library.generateUuid()
	end

	-- 3. Create the task in Kanboard.
	local params = {
		title = task.text,
		description = "Task Status in SB at creation: [" .. task.status .. "]",
		reference = pageId,
		project_id = projectId
	}
	if swimlaneId ~= nil and swimlaneId ~= "" and tostring(swimlaneId) ~= "0" then
		params.swimlane_id = swimlaneId
	end
	local response = Kanboard.rpc("createTask", params)
	local taskId
	if Kanboard.checkResponse(response) then
		taskId = response.body.result
	else
		Library.notify(Library.ERROR, "Unable to create Kanboard task.")
		return
	end

	-- 4. Close the task if required.
	if task.status == "x" or task.status == "X" then
		response = Kanboard.rpc("closeTask", {
			task_id = taskId
		})
		if not Kanboard.checkResponse(response) then
			Library.notify(Library.ERROR, "Unable to close Kanboard task.")
			return
		end
	end

	-- 5. Update the KB task with a permanent link to the SB page.
	response = Kanboard.rpc("createExternalTaskLink", {
		task_id = taskId,
		url = config.get("kanboard").sbBaseUrl .. "/pageId:" .. pageId,
		dependency = "related",
		type = "weblink",
		title = "SB Context"
	})
	if not Kanboard.checkResponse(response) then
		Library.notify(Library.ERROR, "Unable to link Kanboard task to SilverBullet.")
		return
	end

	-- 6. Replace the original task with a linked task.
	editor.replaceRange(
		task.start, task.finish, Kanboard.queryTask(taskId))

	-- 7. Persist the pageId in the page frontmatter.
	Library.setFrontmatter("pageId", pageId, false)

	-- 8. Add the task to the local cache.
	local kbTaskResponse = Kanboard.rpc("getTask", {
		task_id = taskId
	})
	if not Kanboard.checkResponse(kbTaskResponse) then
		Library.notify(Library.ERROR, "Unable to retrieve Kanboard task.")
		return
	end
	Kanboard.updateCache(projectId, kbTaskResponse.body.result)
	Library.notify(Library.INFO, "Task sent to Kanboard.")
end

-----------------------------------------------------------------------
-- Kanboard.getReferenceData(projectId)
--
-- Get reference data for given projectId.
--
-- Returns a table with project, columns and categories.
-----------------------------------------------------------------------
function Kanboard.getReferenceData(projectId)
	-- Retrieve project
	local response = Kanboard.rpc("getProjectById", {
		project_id = projectId
	})
	local project
	if Kanboard.checkResponse(response) then
		project = response.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve project.")
		return
	end

	-- Retrieve columns
	local response = Kanboard.rpc("getColumns", {
		project_id = projectId
	})
	local columns = {}
	if Kanboard.checkResponse(response) then
		columns = response.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve columns.")
		return
	end

	-- Retrieve categories
	response = Kanboard.rpc("getAllCategories", {
		project_id = projectId
	})
	local categories = {}
	if Kanboard.checkResponse(response) then
		categories = response.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve categories.")
		return
	end

	-- Retrieve swimlanes
	local swimlaneResponse = Kanboard.rpc("getAllSwimlanes", {
		project_id = projectId
	})
	local swimlanes = {}
	if Kanboard.checkResponse(swimlaneResponse) then
		swimlanes = swimlaneResponse.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve swimlanes.")
		return
	end

	-- Retrive users
	local userResponse = Kanboard.rpc("getProjectUsers", { project_id = projectId })
	local users = {}
	if Kanboard.checkResponse(userResponse) then
		users = userResponse.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve users.")
		return
	end

	return {
		project = project,
		columns = columns,
		categories = categories,
		swimlanes = swimlanes,
		users = users
	}
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
function Kanboard.updateCache(projectId, kbTask)
	-- Retrieve project.
	local response = Kanboard.rpc("getProjectById", {
		project_id = projectId
	})
	local project = {}
	if Kanboard.checkResponse(response) then
		project = response.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve project.")
		return
	end

	local reference = Kanboard.getReferenceData(projectId)

	-- Decide between full rebuild and incremental update.
	-- Use the project ID so cache pages remain unique even when names collide.
	local cachePage = config.get("kanboard").sbCachePath .. "/" .. tostring(project.id)
	local cacheMeta = query [[from index.subPages(config.get("kanboard").sbCachePath) where projectId == projectId]]
	if (cacheMeta == nil) or (#cacheMeta == 0) or (kbTask == nil) then
		Kanboard.rebuildCache(project, cachePage, reference)
		return
	else
		local age = os.time() - (tonumber(cacheMeta[1].lastSync) or 0)
		Library.notify(Library.DEBUG, "Kanboarddebug: cache Age =" ..
			age .. " now =" .. os.time() .. " lastSync =" .. tostring(cacheMeta[1].lastSync))
		if age > config.get("kanboard").sbCacheRefreshHours * 3600 then
			Kanboard.updateAllCaches() -- here we trigger a full rebuild of all caches, to avoid loosing closed tasks.make
			return
		end
	end
	Kanboard.updateCacheEntry(kbTask, cachePage, reference)
end

-----------------------------------------------------------------------
-- rebuildCache(project, cachePage, columns, categories)
--
-- Rebuilds a project's cache from Kanboard.
-----------------------------------------------------------------------
function Kanboard.rebuildCache(project, cachePage, reference)
	-- Retrieve all tasks.
	local response = Kanboard.rpc("getAllTasks", {
		project_id = project.id
	})
	local tasks
	if Kanboard.checkResponse(response) then
		tasks = response.body.result
	else
		Library.notify(Library.ERROR, "Unable to retrieve tasks.")
		return
	end

	-- Build page.
	local page = {}
	table.insert(page, "---")
	table.insert(page, "pageId: " .. Library.generateUuid())
	table.insert(page, "projectId: " .. project.id)
	table.insert(page, "projectName: " .. project.name)
	table.insert(page, "project: \n" .. yaml.stringify(project))
	table.insert(page, "swimlanes: \n" .. yaml.stringify(reference.swimlanes))
	table.insert(page, "columns: \n" .. yaml.stringify(reference.columns))
	table.insert(page, "categories: \n" .. yaml.stringify(reference.categories))
	table.insert(page, "users: \n" .. yaml.stringify(reference.users))
	table.insert(page, "tags: \n- KanboardManaged\n- meta")
	table.insert(page, "lastSync: " .. os.time())
	table.insert(page, "---")
	table.insert(page, "")
	table.insert(page, "[Kanban board](" .. project.url.board .. ")")
	table.insert(page, "")
	for _, task in ipairs(tasks) do
		local entry = Kanboard.buildCacheEntry(task, reference)
		if not entry then
			return
		end
		table.insert(page, entry)
		table.insert(page, "")
	end
	space.writePage(
		cachePage, table.concat(page, "\n"))
	Library.notify(Library.INFO, "Kanboard: Cache project " ..
		project.id .. " " .. project.name .. " rebuilt (" .. # tasks .. " tasks).")
end

-----------------------------------------------------------------------
-- updateCacheEntry(kbTask, cachePage, columns, categories)
--
-- Updates or appends a single cache entry.
-----------------------------------------------------------------------
function Kanboard.updateCacheEntry(kbTask, cachePage, reference)
	local entry = Kanboard.buildCacheEntry(kbTask, reference)
	if not entry then
		return
	end

	-------------------------------------------------------------------
	-- Locate the cached task.
	-------------------------------------------------------------------
	local tasks = query [[
        from index.tag "task"
        where page == cachePage
          and kbId == tostring(kbTask.id)
    ]]
	local text = space.readPage(cachePage)
	if # tasks == 0 then
		text = text .. "\n" .. entry .. "\n"
	elseif # tasks == 1 then
		-- Replace.
		local task = tasks[1]
		text = text:sub(1, task.pos - 1) .. entry .. text:sub(task.toPos + 1)
	else
		Library.notify(Library.ERROR, "Cache contains duplicate kbId - perform a full update" .. kbTask.id)
		return
	end
	space.writePage(cachePage, text)
end

-----------------------------------------------------------------------
-- Kanboard.getCategory(reference, categoryId)
--
-- Retrieves a category by its ID from the reference data.
-----------------------------------------------------------------------
function Kanboard.getCategory(reference, categoryId)
	if categoryId ~= "0" then
		local category
		_, category = table.find(reference.categories, function(category)
			return category.id == categoryId
		end)
		return category
	end
	return nil
end

-----------------------------------------------------------------------
-- Kanboard.getSwimlane(reference, swimlaneId)
--
-- Retrieves a swimlane by its ID from the reference data.
-----------------------------------------------------------------------
function Kanboard.getSwimlane(reference, swimlaneId)
	if swimlaneId ~= "0" then
		local swimlane
		_, swimlane = table.find(reference.swimlanes, function(swimlane)
			return swimlane.id == swimlaneId
		end)
		return swimlane
	end
	return nil
end

-----------------------------------------------------------------------
-- Kanboard.getSwimlaneAtPosition(reference, position)
--
-- Retrieves a swimlane by its Position from the reference data.
-----------------------------------------------------------------------
function Kanboard.getSwimlaneAtPosition(reference, position)
	if position ~= "0" then
		local swimlane
		_, swimlane = table.find(reference.swimlanes, function(swimlane)
			return swimlane.position == position
		end)
		return swimlane
	end
	return nil
end

-----------------------------------------------------------------------
-- Kanboard.getColumn(reference, columnId)
--
-- Retrieves a column by its ID from the reference data.
-----------------------------------------------------------------------
function Kanboard.getColumn(reference, columnId)
	if columnId ~= "0" then
		local column
		_, column = table.find(reference.columns, function(column)
			return column.id == columnId
		end)
		return column
	end
	return nil
end

-----------------------------------------------------------------------
-- Kanboard.getColumnAtPosition(reference, position)
--
-- Retrieves a column by its Position from the reference data.
-----------------------------------------------------------------------
function Kanboard.getColumnAtPosition(reference, position)
	if position ~= "0" then
		local column
		_, column = table.find(reference.columns, function(column)
			return column.position == position
		end)
		return column
	end
	return nil
end

-----------------------------------------------------------------------
-- Kanboard.getUserName(reference, userId)
--
-- Retrieves a user name by their ID from the reference data.
-----------------------------------------------------------------------
function Kanboard.getUserName(reference, userId)
	local user
	return (reference.users)[userId]
end

-----------------------------------------------------------------------
-- Kanboard.addAttribute(table, value)
--
-- wrapper around table.insert resilient to nil values.
-----------------------------------------------------------------------
function Kanboard.addAttribute(attributes, name, value)
	if value == nil or name == nil then
		return
	end
	table.insert(attributes, "[" .. name .. ": " .. value .. "]")
end

-----------------------------------------------------------------------
-- buildCacheEntry(task, reference)
--
-- Builds the canonical representation of a Kanboard task in the local
-- cache.
--
-- This is the single point of maintenance for the cache format.
--
-- input: task: Kanboard task objects
--        reference: table with reference data (in particular
--                   columns and categories)
-----------------------------------------------------------------------
function Kanboard.buildCacheEntry(task, reference)
	-- Build status.
	local status = " "
	if task.is_active == "0" then
		status = "x"
	end

	-- Build Tags
	local tagList = {}
	local response = Kanboard.rpc("getTaskTags", { task_id = task.id })
	local tags
	if Kanboard.checkResponse(response) then
		tags = response.body.result
		for _, tag in pairs(tags) do
			tag = tag:gsub("[<>]", "") -- Remove any angle brackets from the tag to avoid issues with tags in angle brackets.
			table.insert(tagList, "#<" .. tag .. ">")
		end
	else
		Library.notify(Library.ERROR, "Unable to retrieve task tags.")
		return nil
	end

	-- Build description
	-- TODO: need to find a way to embed Description in the cache entry without breaking the task item format.

	-- Build attributes
	local attributes = {}
	Kanboard.addAttribute(attributes, "kbId", task.id)
	if task.category_id ~= 0 and task.category_id ~= "0" then
		Kanboard.addAttribute(attributes, "category", (Kanboard.getCategory(reference, task.category_id))["name"])
	end
	Kanboard.addAttribute(attributes, "categoryId", task.category_id)
	Kanboard.addAttribute(attributes, "priority", task.score)
	Kanboard.addAttribute(attributes, "project", reference.project.name)
	Kanboard.addAttribute(attributes, "projectId", task.project_id)
	Kanboard.addAttribute(attributes, "column", (Kanboard.getColumn(reference, task.column_id))["title"])
	Kanboard.addAttribute(attributes, "columnId", task.column_id)
	Kanboard.addAttribute(attributes, "createdRaw", task.date_creation)
	Kanboard.addAttribute(attributes, "created", os.date("%Y-%m-%d %H:%M:%S", task.date_creation))
	Kanboard.addAttribute(attributes, "dueRaw", task.date_due)
	Kanboard.addAttribute(attributes, "due", os.date("%Y-%m-%d %H:%M:%S", task.date_due))
	Kanboard.addAttribute(attributes, "modifiedRaw", task.date_modification)
	Kanboard.addAttribute(attributes, "modified", os.date("%Y-%m-%d %H:%M:%S", task.date_modification))
	Kanboard.addAttribute(attributes, "movedRaw", task.date_moved)
	Kanboard.addAttribute(attributes, "moved", os.date("%Y-%m-%d %H:%M:%S", task.date_moved))
	Kanboard.addAttribute(attributes, "startedRaw", task.date_started)
	Kanboard.addAttribute(attributes, "started", os.date("%Y-%m-%d %H:%M:%S", task.date_started))
	Kanboard.addAttribute(attributes, "completedRaw", task.date_completed)
	Kanboard.addAttribute(attributes, "completed", os.date("%Y-%m-%d %H:%M:%S", task.date_completed))
	Kanboard.addAttribute(attributes, "color", task.color_id)
	-- TODO add colorBackground and colorBorder
	if task.owner_id ~= 0 and task.owner_id ~= "0" then
		Kanboard.addAttribute(attributes, "owner", (Kanboard.getUserName(reference, task.owner_id)))
	end
	Kanboard.addAttribute(attributes, "ownerId", task.owner_id)
	if task.creator_id ~= 0 and task.creator_id ~= "0" then
		Kanboard.addAttribute(attributes, "creator", (Kanboard.getUserName(reference, task.creator_id)))
	end
	Kanboard.addAttribute(attributes, "creatorId", task.creator_id)
	Kanboard.addAttribute(attributes, "position", task.position)
	Kanboard.addAttribute(attributes, "swimlane", (Kanboard.getSwimlane(reference, task.swimlane_id))["name"])
	Kanboard.addAttribute(attributes, "swimlaneId", task.swimlane_id)
	Kanboard.addAttribute(attributes, "recurrenceStatus", task.recurrence_status)
	Kanboard.addAttribute(attributes, "recurrenceBasedate", task.recurrence_basedate)
	Kanboard.addAttribute(attributes, "recurrenceChild", task.recurrence_child)
	Kanboard.addAttribute(attributes, "recurrenceFactor", task.recurrence_factor)
	Kanboard.addAttribute(attributes, "recurrenceParent", task.recurrence_parent)
	Kanboard.addAttribute(attributes, "recurrenceTimeframe", task.recurrence_timeframe)
	Kanboard.addAttribute(attributes, "recurrenceTrigger", task.recurrence_trigger)
	Kanboard.addAttribute(attributes, "pageId", task.reference)
	Kanboard.addAttribute(attributes, "timeEstimated", task.time_estimated)
	Kanboard.addAttribute(attributes, "timeSpent", task.time_spent)

	return string.format("* [%s] %s ([KB](%s)) %s %s", status, task.title, task.url, table.concat(tagList, " "),
		table.concat(attributes, " "))
end

-----------------------------------------------------------------------
-- Kanboard.getLastColumnId(columns)
--
-- Returns the ID of the last column in the provided Kanboard column list.
-----------------------------------------------------------------------
function Kanboard.getLastColumnId(columns)
	local lastColumnId = nil
	local maxPosition = 0
	for _, column in ipairs(columns) do
		local position = tonumber(column.position) or 0
		if position >= maxPosition then
			maxPosition = position
			lastColumnId = column.id
		end
	end
	return lastColumnId
end

-----------------------------------------------------------------------
-- closeTasks()
--
-- Closes tasks marked as done in the cached page on Kanboard
-- This can be achieved by closing the tasks and/or moving them to the last column.
-- see config.kbCloseDone and config.kbMoveDone
-----------------------------------------------------------------------
function Kanboard.closeTasks()
	local cfg = config.get("kanboard")
	if not cfg.kbCloseDone and not cfg.kbMoveDone then
		Library.notify(Library.DEBUG,
			"Kanboard: No sync action configured (kbCloseDone and kbMoveDone are both false).")
		return
	end

	local closedTasks = query [[from t=tags.task where string.startsWith(t.page, cfg.sbCachePath) and t.done]]
	if #closedTasks == 0 then
		Library.notify(Library.DEBUG, "Kanboard: No closed tasks found to sync.")
		return
	end

	local closedCount = 0
	local movedCount = 0
	local failedCount = 0

	for _, task in ipairs(closedTasks) do
		-- Validate that the task is still in kanboard
		local taskResponse = Kanboard.rpc("getTask", { task_id = task.kbId })
		local kbTask = nil
		if Kanboard.checkResponse(taskResponse) then
			kbTask = taskResponse.body.result
		end
		if not kbTask then
			Library.notify(Library.WARNING, "Task not found in Kanboard: " .. tostring(task.kbId))
			failedCount = failedCount + 1
		else
			-- Get the last column id if required
			local lastColumnId = nil
			if cfg.kbMoveDone then
				local columnsResponse = Kanboard.rpc("getColumns", { project_id = kbTask.project_id })
				if not Kanboard.checkResponse(columnsResponse) then
					Library.notify(Library.ERROR, "Unable to retrieve columns.")
					return
				end
				local columns = columnsResponse.body.result
				lastColumnId = Kanboard.getLastColumnId(columns)
			end
			if lastColumnId then
				local moveResponse = Kanboard.rpc("moveTaskPosition", {
					project_id = kbTask.project_id,
					swimlane_id = kbTask.swimlane_id,
					task_id = task.kbId,
					column_id = lastColumnId,
					position = 1
				})
				if Kanboard.checkResponse(moveResponse) then
					movedCount = movedCount + 1
				else
					failedCount = failedCount + 1
				end
			end
			if cfg.kbCloseDone then
				local closeResponse = Kanboard.rpc("closeTask", { task_id = task.kbId })
				if Kanboard.checkResponse(closeResponse) then
					closedCount = closedCount + 1
				else
					failedCount = failedCount + 1
				end
			end
		end
	end

	if closedCount > 0 or movedCount > 0 then
		Library.notify(Library.INFO,
			"Kanboard: Updated tasks: Closed " .. closedCount .. ", Moved " .. movedCount .. ".")
	end
	if failedCount > 0 then
		Library.notify(Library.ERROR, "Kanboard: Failed to sync " .. failedCount .. " task(s).")
	end
end

-----------------------------------------------------------------------
-- Send current task to Kanboard.
-----------------------------------------------------------------------
command.define {
	name = "Kanboard: Send Task",
	mac = "Ctrl-Cmd-a",
	key = "Ctrl-Alt-a",
	run = function()
		local pageMeta = editor.getCurrentPageMeta()
		local projectId = pageMeta.kbProjectId or config.get("kanboard").kbProjectId
		Kanboard.sendTask(projectId, pageMeta.kbSwimlaneId)
	end
}

-----------------------------------------------------------------------
-- pruneCaches(projects)
--
-- Deletes the cache pages of projects that Kanboard no longer returns:
-- closed or deleted projects, and projects the user is no longer a
-- member of. getMyProjects lists active projects only, so without this
-- their cache pages would stay forever with stale tasks.
--
-- input: projects: the project list returned by getMyProjects
--
-- Only a page that is tagged KanboardManaged, has a projectId in its
-- frontmatter and is named <sbCachePath>/<projectId> is deleted, so
-- nothing but a cache page written by rebuildCache can be removed.
--
-- Returns:
--   the number of cache pages deleted
-----------------------------------------------------------------------
function Kanboard.pruneCaches(projects)
	local cachePath = config.get("kanboard").sbCachePath
	local active = {}
	for _, project in ipairs(projects) do
		if project.id then
			active[tostring(project.id)] = true
		end
	end

	local pages = query [[from p = index.subPages(cachePath)
		where table.includes(p.tags, "KanboardManaged")
		]]
	local pruned = 0
	for _, page in ipairs(pages or {}) do
		local projectId = page.projectId
		if projectId ~= nil
			and page.name == cachePath .. "/" .. tostring(projectId)
			and not active[tostring(projectId)] then
			local ok, err = pcall(function()
				space.deletePage(page.name)
			end)
			if ok then
				pruned = pruned + 1
				Library.notify(Library.INFO, "Kanboard: Removed cache of closed or deleted project " ..
					tostring(projectId) .. ".")
			else
				Library.notify(Library.ERROR, "Unable to delete cache page '" .. page.name .. "': " ..
					tostring(err))
			end
		end
	end
	return pruned
end

-----------------------------------------------------------------------
-- Update all project caches by cycling through all Kanboard projects.
--
-- Workflow:
--   1. Sync tasks marked as done in SB back to Kanboard.
--   2. Retrieve the user's active projects.
--   3. Delete the caches of projects no longer returned (pruneCaches).
--   4. Rebuild the cache of every active project.
-----------------------------------------------------------------------
function Kanboard.updateAllCaches()
	Kanboard.closeTasks()
	local response = Kanboard.rpc("getMyProjects", {})
	if not Kanboard.checkResponse(response) then
		Library.notify(Library.ERROR, "Unable to retrieve Kanboard projects.")
		return
	end
	local projects = response.body.result
	-- A JSON-RPC error arrives with HTTP 200 and no result: never prune then,
	-- or a failed call would delete every cache.
	if type(projects) ~= "table" then
		Library.notify(Library.ERROR, "Unable to retrieve Kanboard projects.")
		return
	end
	Kanboard.pruneCaches(projects)
	if #projects == 0 then
		Library.notify(Library.INFO, "Kanboard: No projects found.")
		return
	end

	for _, project in ipairs(projects) do
		if project.id then
			Kanboard.updateCache(project.id)
		end
	end

	Library.notify(Library.INFO, "Kanboard: Updated cache for " .. #projects .. " project(s).")
end

-----------------------------------------------------------------------
-- Rebuild the Kanboard cache.
-----------------------------------------------------------------------
command.define {
	name = "Kanboard: Update Cache",
	run = function()
		Kanboard.updateAllCaches()
	end
}

-----------------------------------------------------------------------
-- Remove Kanboard cache pages tagged as managed by this Library.
-----------------------------------------------------------------------
command.define {
	name = "Kanboard: Remove Cache",
	run = function()
		local pages = query [[from p = index.pages()
			where table.includes(p.tags, "KanboardManaged")
			]]
		if not pages or #pages == 0 then
			Library.notify(Library.INFO, "No Kanboard cache pages found.")
			return
		end

		local confirmed = editor.confirm(
			"Delete " .. #pages .. " Kanboard cache page(s)?",
			false
		)
		if not confirmed then
			return
		end

		for _, page in ipairs(pages) do
			local ok, err = pcall(function()
				space.deletePage(page.name)
			end)
			if not ok then
				Library.notify(Library.ERROR, "Unable to delete page '" .. page.name .. "': " .. tostring(err))
			end
		end

		Library.notify(Library.INFO, "Removed " .. #pages .. " Kanboard cache page(s).")
	end
}

-----------------------------------------------------------------------
-- slashcommand:get Tasks by PageId
--
-- Slash command used to retrieve tasks from Kanboard.
-----------------------------------------------------------------------
slashCommand.define {
	name = "getTasks",
	run = function()
		local meta = editor.getCurrentPageMeta()
		local text = "${query[[from index.tasks() where pageId == \"" ..
			meta.pageId .. "\" select templates.taskItem(_)]]}"
		editor.insertAtCursor(text, false, false)
	end
}

-----------------------------------------------------------------------
-- slashcommand:get Tasks by ProjectId
--
-- Slash command used to retrieve tasks from Kanboard.
-----------------------------------------------------------------------
slashCommand.define {
	name = "getTasksByProjectId",
	run = function()
		local meta = editor.getCurrentPageMeta()
		local text = "${query[[from index.tasks() where projectId == " ..
			meta.kbProjectId .. " select templates.taskItem(_)]]}"
		editor.insertAtCursor(text, false, false)
	end
}
