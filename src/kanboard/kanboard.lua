-----------------------------------------------------------------------
-- Package
-----------------------------------------------------------------------
Kanboard = {}

-----------------------------------------------------------------------
-- queryTask(task)
--
-- Converts a Kanboard task into a reference to a cached task.
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
-- In case of failure an error notification is shown.
-----------------------------------------------------------------------
function Kanboard.checkResponse(response)
	if config.get("kanboard").debug then
		if response.ok then
			editor.flashNotification("Kanboarddebug: HTTP Response OK", "info")
		else
			editor.flashNotification("Kanboarddebug: " .. tostring(response.status), "info")
		end
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
		editor.flashNotification("No task found.", "error")
		return
	end

	-- 2. Get a pageId for the current page.
	local pageId = editor.getCurrentPageMeta().pageId
	if pageId == nil or pageId == "" then
		pageId = Library.generateUuid()
	end

	-- 3. Create the task in Kanboard.
	params = {
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
		editor.flashNotification("Unable to create Kanboard task.", "error")
		return
	end

	-- 4. Close the task if required.
	if task.status == "x" or task.status == "X" then
		response = Kanboard.rpc("closeTask", {
			task_id = taskId
		})
		if not Kanboard.checkResponse(response) then
			editor.flashNotification("Unable to close Kanboard task.", "error")
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
		editor.flashNotification("Unable to link Kanboard task to SilverBullet.", "error")
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
		editor.flashNotification("Unable to retrieve Kanboard task.", "error")
		return
	end
	Kanboard.updateCache(projectId, kbTaskResponse.body.result)
	editor.flashNotification("Task sent to Kanboard.")
end

-----------------------------------------------------------------------
-- getReferenceData(projectId)
--
-- get reference data for given projectId.
--
-- Returns a table with project, columns and categories.
-----------------------------------------------------------------------
function Kanboard.getReferenceData(projectId)
	-- Retrieve columns names.
	local response = Kanboard.rpc("getColumns", {
		project_id = projectId
	})
	local columns = {}
	if Kanboard.checkResponse(response) then
		columns = response.body.result
	else
		editor.flashNotification("Unable to retrieve columns.", "error")
		return
	end

	-- Retrieve categories names.
	response = Kanboard.rpc("getAllCategories", {
		project_id = projectId
	})
	local categories = {}
	if Kanboard.checkResponse(response) then
		categories = response.body.result
	else
		editor.flashNotification("Unable to retrieve categories.", "error")
		return
	end

	-- Retrieve swimlanes names.
	local swimlaneResponse = Kanboard.rpc("getAllSwimlanes", {
		project_id = projectId
	})
	local swimlanes = {}
	if Kanboard.checkResponse(swimlaneResponse) then
		swimlanes = swimlaneResponse.body.result
	else
		editor.flashNotification("Unable to retrieve swimlanes.", "error")
		return
	end

	return {
		columns = columns,
		categories = categories,
		swimlanes = swimlanes,
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
	local project
	if Kanboard.checkResponse(response) then
		project = response.body.result
	else
		editor.flashNotification("Unable to retrieve project.", "error")
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
		if (config.get("kanboard").debug) then
			editor.flashNotification("Kanboarddebug: cache Age =" ..
				age .. " now =" .. os.time() .. " lastSync =" .. cacheMeta[1].lastSync)
		end
		if age > config.get("kanboard").sbCacheRefreshHours * 3600 then
			Kanboard.rebuildCache(project, cachePage, reference)
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
		editor.flashNotification("Unable to retrieve tasks.", "error")
		return
	end

	-- Build page.
	local page = {}
	table.insert(page, "---")
	table.insert(page, "pageId: " .. Library.generateUuid())
	table.insert(page, "projectId: " .. project.id)
	table.insert(page, "projectName: " .. project.name)
	table.insert(page, "swimlanes: \n" .. yaml.stringify(reference.swimlanes))
	table.insert(page, "columns: \n" .. yaml.stringify(reference.columns))
	table.insert(page, "categories: \n" .. yaml.stringify(reference.categories))
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
	editor.flashNotification("Kanboard: Cache project " ..
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
		editor.flashNotification("Cache contains duplicate kbId - perform a full update" .. kbTask.id, "error")
		return
	end
	space.writePage(cachePage, text)
end

-----------------------------------------------------------------------
-- getCategory(reference, categoryId)
--
-- Retrieves a category by its ID from the reference data.
-----------------------------------------------------------------------
function getCategory(reference, categoryId)
	if categoryId ~= "0" then
		_, category = table.find(reference.categories, function(category)
			return category.id == categoryId
		end)
		return category
	end
	return nil
end

-----------------------------------------------------------------------
-- getSwimlane(reference, swimlaneId)
--
-- Retrieves a swimlane by its ID from the reference data.
-----------------------------------------------------------------------
function getSwimlane(reference, swimlaneId)
	if swimlaneId ~= "0" then
		_, swimlane = table.find(reference.swimlanes, function(swimlane)
			return swimlane.id == swimlaneId
		end)
		return swimlane
	end
	return nil
end

-----------------------------------------------------------------------
-- getSwimlaneAtPosition(reference, position)
--
-- Retrieves a swimlane by its Position from the reference data.
-----------------------------------------------------------------------
function getSwimlaneAtPosition(reference, position)
	if position ~= "0" then
		_, swimlane = table.find(reference.swimlanes, function(swimlane)
			return swimlane.position == position
		end)
		return swimlane
	end
	return nil
end

-----------------------------------------------------------------------
-- getColumn(reference, columnId)
--
-- Retrieves a column by its ID from the reference data.
-----------------------------------------------------------------------
function getColumn(reference, columnId)
	if columnId ~= "0" then
		_, column = table.find(reference.columns, function(column)
			return column.id == columnId
		end)
		return column
	end
	return nil
end

-----------------------------------------------------------------------
-- getColumnAtPosition(reference, position)
--
-- Retrieves a column by its Position from the reference data.
-----------------------------------------------------------------------
function getColumnAtPosition(reference, position)
	if position ~= "0" then
		_, column = table.find(reference.columns, function(column)
			return column.position == position
		end)
		return column
	end
	return nil
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
	-- Retrieve tags.
	local response = Kanboard.rpc("getTaskTags", {
		task_id = task.id
	})
	local tags
	if Kanboard.checkResponse(response) then
		tags = response.body.result
	else
		editor.flashNotification("Unable to retrieve task tags.", "error")
		return nil
	end

	-- Build status.
	local status = " "
	if task.is_active == "0" then
		status = "x"
	end
	local tagList = {}
	local attributes = {}

	-- Build tags.
	if task.category_id ~= "0" then
		local category = getCategory(reference, task.category_id)
		if category then
			table.insert(attributes, "[category: " .. category.name .. "]")
			table.insert(attributes, "[categoryId: " .. task.category_id .. "]")
			local categoryName = category.name:gsub("[<>]", "")
			table.insert(tagList, "#<category-" .. categoryName .. ">")
		end
	end
	for _, tag in pairs(tags) do
		tag = tag:gsub("[<>]", "")
		table.insert(tagList, "#<" .. tag .. ">")
	end

	-- Build attributes.
	table.insert(attributes, "[kbId: " .. task.id .. "]")
	local column = getColumn(reference, task.column_id)
	if column then
		table.insert(attributes, "[column: " .. column.title .. "]")
	end
	if task.project_id ~= "0" then
		table.insert(
			attributes, "[projectId: " .. task.project_id .. "]")
			attributes, "[projectName: " .. reference.project.name .. "]")
	end
	if task.date_due ~= "0" then
		table.insert(
			attributes, "[due: " .. os.date("%Y-%m-%d", tonumber(task.date_due)) .. "]")
	end
	if task.score ~= "0" then
		table.insert(
			attributes, "[priority: " .. task.score .. "]")
	end
	if task.position ~= "0" then
		table.insert(
			attributes, "[position: " .. task.position .. "]")
	end
	if task.swimlane_id ~= "0" then
		local swimlane = getSwimlane(reference, task.swimlane_id)
		if swimlane then
			table.insert(
				attributes, "[swimlaneId: " .. task.swimlane_id .. "]")
			table.insert(
				attributes, "[swimlaneName: " .. swimlane.name .. "]")
		end
	end
	if task.recurrence_status ~= "0" then
		table.insert(
			attributes, "[recurrence: " .. task.recurrence_status .. "]")
	end
	if task.reference ~= "" then
		table.insert(
			attributes, "[pageId: " .. task.reference .. "]")
	end
	return string.format("* [%s] %s ([KB](%s)) %s %s", status, task.title, task.url, table.concat(tagList, " "),
		table.concat(attributes, " "))
end

-----------------------------------------------------------------------
-- findLastColumnId(columns)
--
-- Returns the ID of the last column in the provided Kanboard column list.
-----------------------------------------------------------------------
function Kanboard.findLastColumnId(columns)
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
-- closeTasks(projectId)
--
-- Closes tasks marked as done in the cached page on Kanboard
-- This can be achieved by closing the tasks and/or moving them to the last column.
-- see config.kbCloseDone and config.kbMoveDone
-----------------------------------------------------------------------
function Kanboard.closeTasks(projectId)
	local cfg = config.get("kanboard")
	if not cfg.kbCloseDone and not cfg.kbMoveDone then
		editor.flashNotification("Kanboard: No sync action configured (kbCloseDone and kbMoveDone are both false).",
			"info")
		return
	end

	local response = Kanboard.rpc("getProjectById", {
		project_id = projectId
	})
	if not Kanboard.checkResponse(response) then
		editor.flashNotification("Unable to retrieve project.", "error")
		return
	end
	local project = response.body.result

	local cachePage = cfg.sbCachePath .. "/" .. tostring(project.id)
	local closedTasks = query [[from t=tags.task where t.page == "Kanboard/To-Do" and t.done]]
	if #closedTasks == 0 then
		editor.flashNotification("Kanboard: No closed tasks found to sync.", "info")
		return
	end

	local lastColumnId = nil
	if cfg.kbMoveDone then
		local columnsResponse = Kanboard.rpc("getColumns", { project_id = projectId })
		if not Kanboard.checkResponse(columnsResponse) then
			editor.flashNotification("Unable to retrieve columns.", "error")
			return
		end
		local columns = columnsResponse.body.result
		lastColumnId = Kanboard.findLastColumnId(columns)
	end

	local closedCount = 0
	local movedCount = 0
	local failedCount = 0

	for _, task in ipairs(closedTasks) do
		if lastColumnId then
			local moveResponse = Kanboard.rpc("moveTaskPosition", {
				project_id = projectId,
				swimlane_id = task.swimlaneId,
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

	if closedCount > 0 or movedCount > 0 then
		Kanboard.updateCache(projectId)
		editor.flashNotification("Kanboard: Updated tasks: Closed " .. closedCount .. ", Moved " .. movedCount .. ".")
	end
	if failedCount > 0 then
		editor.flashNotification("Kanboard: Failed to sync " .. failedCount .. " task(s).")
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
-- Update all project caches by cycling through all Kanboard projects.
-----------------------------------------------------------------------
function Kanboard.updateAllCaches()
	local response = Kanboard.rpc("getMyProjects", {})
	if not Kanboard.checkResponse(response) then
		editor.flashNotification("Unable to retrieve Kanboard projects.", "error")
		return
	end
	local projects = response.body.result
	if not projects or #projects == 0 then
		editor.flashNotification("Kanboard: No projects found.", "info")
		return
	end

	for _, project in ipairs(projects) do
		if project.id then
			Kanboard.updateCache(project.id)
		end
	end

	editor.flashNotification("Kanboard: Updated cache for " .. #projects .. " project(s).")
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
			editor.flashNotification("No Kanboard cache pages found.", "info")
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
				editor.flashNotification("Unable to delete page '" .. page.name .. "': " .. tostring(err), "error")
			end
		end

		editor.flashNotification("Removed " .. #pages .. " Kanboard cache page(s).")
	end
}

-----------------------------------------------------------------------
-- Sync locally closed Kanboard tasks.
-----------------------------------------------------------------------
command.define {
	name = "Kanboard: Sync Status",
	run = function()
		local projectId = editor.getCurrentPageMeta().kbProjectId
		Kanboard.closeTasks(projectId)
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
