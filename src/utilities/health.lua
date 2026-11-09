
-----------------------------------------------------------------------
-- Package utilities (health)
--
-- The health table of the space: ${utilities.health()} shows one row
-- per check with a count and a link to the check's detail, the
-- virtual page health:<key>.
--
-- A check either lists rows (pages, tasks, ...), which are its detail
-- and whose number is its count, or reads a count from the report page
-- of the MCP server's scan. Both the table and the detail pages call
-- the same functions, so they cannot disagree.
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- utilities.mcpReport()
--
-- Reads the report page of the MCP server's scan from the index: the
-- counts in the headings "Findings (N)" and "Files that are not pages
-- (N)", and whether the list item "Rendering: ..." says it is blocked.
--
-- Returns:
--   Table { findings, files, blocked }, or nil when the page has no
--   such headings (not installed, not indexed yet).
-----------------------------------------------------------------------
function utilities.mcpReport()
	local name = utilities.config().mcpPage
	local report = { blocked = false }
	local headers = query[[from h = index.tag "header" where h.page == name]]
	for _, h in ipairs(headers) do
		local findings = string.match(h.name, "^Findings %((%d+)%)")
		if findings then report.findings = tonumber(findings) end
		local files = string.match(h.name, "^Files that are not pages %((%d+)%)")
		if files then report.files = tonumber(files) end
	end
	if report.findings == nil and report.files == nil then return nil end
	local items = query[[from i = index.tag "item" where i.page == name]]
	for _, i in ipairs(items) do
		if i.text and string.startsWith(i.text, "Rendering:") and string.find(i.text, "blocked", 1, true) then
			report.blocked = true
		end
	end
	return report
end

-----------------------------------------------------------------------
-- utilities.hasConflictMarkers(text)
--
-- Whether a page text holds a conflict: a line starting with
-- "<<<<<<<", a later "=======" and a later ">>>>>>>". This is what
-- SilverBullet writes when two edits cannot be merged.
-----------------------------------------------------------------------
function utilities.hasConflictMarkers(text)
	local padded = "\n" .. text
	local start = string.find(padded, "\n<<<<<<<", 1, true)
	if not start then return false end
	local separator = string.find(padded, "\n=======", start, true)
	if not separator then return false end
	return string.find(padded, "\n>>>>>>>", separator, true) ~= nil
end

-----------------------------------------------------------------------
-- utilities.conflicts()
--
-- Pages and files in conflict: copies whose name holds ".conflicted"
-- (written by older versions of SilverBullet, and by 2.12 for files it
-- cannot merge), and pages holding conflict markers. A page with
-- markers keeps only its name in the index, so this reads every page
-- that is not excluded.
--
-- Returns:
--   Rows { page, kind }.
-----------------------------------------------------------------------
function utilities.conflicts()
	local rows = {}
	for _, p in ipairs(query[[from p = index.pages() order by p.name]]) do
		if not utilities.excluded(p.name) then
			if string.find(p.name, ".conflicted", 1, true) then
				table.insert(rows, { utilities.link(p.name), "copy" })
			elseif utilities.hasConflictMarkers(space.readPage(p.name)) then
				table.insert(rows, { utilities.link(p.name), "conflict markers" })
			end
		end
	end
	for _, d in ipairs(query[[from d = index.documents() order by d.name]]) do
		if not utilities.excluded(d.name) and string.find(d.name, ".conflicted", 1, true) then
			table.insert(rows, { utilities.code(d.name), "copy" })
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.aspiring()
--
-- Links to pages that do not exist, from pages that are not excluded.
--
-- Returns:
--   Rows { missing page, linked from }, one per missing page.
-----------------------------------------------------------------------
function utilities.aspiring()
	local from, names = {}, {}
	for _, a in ipairs(query[[from a = index.aspiringPages() order by a.name]]) do
		if not utilities.excluded(a.page) then
			if not from[a.name] then
				from[a.name] = {}
				table.insert(names, a.name)
			end
			from[a.name][a.page] = true
		end
	end
	local rows = {}
	for _, name in ipairs(names) do
		local pages = {}
		for page in pairs(from[name]) do table.insert(pages, page) end
		table.sort(pages)
		local links = {}
		for _, page in ipairs(pages) do table.insert(links, utilities.link(page)) end
		table.insert(rows, { utilities.link(name), table.concat(links, ", ") })
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.invalidFrontmatter()
--
-- Formal pages whose frontmatter fails validation. A page is formal
-- when one of its tags is defined (tag.define) with a `schema` or a
-- `validate` function; every other page is informal and never
-- counted. Each such tag is checked as SilverBullet's editor does:
-- jsonschema.validateObject with the schema, then `validate`.
--
-- A tag defined with mustValidate = true keeps a failing page out of
-- the index altogether, so such pages cannot be seen here.
--
-- Returns:
--   Rows { page, tag, error }.
-----------------------------------------------------------------------
function utilities.invalidFrontmatter()
	local definitions = config.get("tags", {}) or {}
	local rows = {}
	for _, p in ipairs(query[[from p = index.pages() order by p.name]]) do
		if not utilities.excluded(p.name) then
			for _, t in ipairs(p.tags or {}) do
				local definition = definitions[t]
				if definition and (definition.schema or definition.validate) then
					local err
					if definition.schema then
						err = jsonschema.validateObject(definition.schema, p)
					end
					if not err and definition.validate then
						local ok, result = pcall(definition.validate, p)
						if not ok then
							err = "validate failed: " .. tostring(result)
						else
							err = result
						end
					end
					if err then
						table.insert(rows, { utilities.link(p.name), utilities.code("#" .. t), utilities.code(err) })
					end
				end
			end
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.decisionsProposed()
--
-- Decision records (pages tagged `dr`) in status `proposed`, waiting
-- for a person to decide.
--
-- Returns:
--   Rows { decision, id, date }.
-----------------------------------------------------------------------
function utilities.decisionsProposed()
	local rows = {}
	for _, p in ipairs(query[[from p = index.tag "dr" where p.tag == "page" order by p.name]]) do
		if not utilities.excluded(p.name) and p.status == "proposed" then
			table.insert(rows, { utilities.link(p.name), utilities.code(p.id), utilities.code(p.date) })
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.decisionsDue()
--
-- Decision records due for review, by the ITAM library's rule and
-- setting: an active status (ITAM.drActive) and `lastReviewed`
-- missing or older than the configured reviewDays. Without ITAM there
-- is no such rule, and the check is not shown.
--
-- Returns:
--   Rows { decision, id, last reviewed }, or nil without ITAM.
-----------------------------------------------------------------------
function utilities.decisionsDue()
	if not (ITAM and ITAM.config and ITAM.drActive) then return nil end
	local limit = utilities.daysAgo(ITAM.config().dr.reviewDays)
	local rows = {}
	for _, p in ipairs(query[[from p = index.tag "dr" where p.tag == "page" order by p.name]]) do
		if not utilities.excluded(p.name) and ITAM.drActive[p.status] then
			local reviewed = utilities.day(p.lastReviewed)
			if reviewed == nil or reviewed < limit then
				table.insert(rows, { utilities.link(p.name), utilities.code(p.id), utilities.code(p.lastReviewed) })
			end
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.openKanboardTasks()
--
-- The open tasks of the Kanboard library's cache (those with a kbId),
-- on pages that are not excluded.
-----------------------------------------------------------------------
function utilities.openKanboardTasks()
	local tasks = {}
	for _, t in ipairs(query[[from t = index.tasks() where t.kbId and not t.done order by t.dueRaw]]) do
		if not utilities.excluded(t.page) then table.insert(tasks, t) end
	end
	return tasks
end

-----------------------------------------------------------------------
-- utilities.tasksOverdue()
--
-- Open Kanboard tasks whose due date is before today.
--
-- Returns:
--   Rows { task, due, page }.
-----------------------------------------------------------------------
function utilities.tasksOverdue()
	local today = utilities.today()
	local rows = {}
	for _, t in ipairs(utilities.openKanboardTasks()) do
		local due = tonumber(t.dueRaw) or 0
		if due > 0 and os.date("%Y-%m-%d", due) < today then
			table.insert(rows, { utilities.code(t.name), os.date("%Y-%m-%d", due), utilities.link(t.page) })
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.tasksWithoutDue()
--
-- Open Kanboard tasks without a due date.
--
-- Returns:
--   Rows { task, column, page }.
-----------------------------------------------------------------------
function utilities.tasksWithoutDue()
	local rows = {}
	for _, t in ipairs(utilities.openKanboardTasks()) do
		if (tonumber(t.dueRaw) or 0) == 0 then
			table.insert(rows, { utilities.code(t.name), utilities.code(t.column), utilities.link(t.page) })
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.waitingForReview()
--
-- Pages under the configured proposedPrefix (for example the folder
-- where agents write) in status `proposed` for more than proposedDays
-- days, waiting for a person's review. The frontmatter `date` counts;
-- a page without one counts from its last change.
--
-- Returns:
--   Rows { page, since }, or nil when no proposedPrefix is configured.
-----------------------------------------------------------------------
function utilities.waitingForReview()
	local settings = utilities.config()
	local prefix = settings.proposedPrefix
	if type(prefix) ~= "string" or prefix == "" then return nil end
	local limit = utilities.daysAgo(settings.proposedDays)
	local rows = {}
	for _, p in ipairs(query[[from p = index.pages() where p.status == "proposed" order by p.name]]) do
		if string.startsWith(p.name, prefix) and not utilities.excluded(p.name) then
			local since = utilities.day(p.date) or utilities.day(p.lastModified)
			if since and since < limit then
				table.insert(rows, { utilities.link(p.name), since })
			end
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- utilities.checks
--
-- The checks of the health table, in order. Each has a title and
-- either
--   detail, columns, rows: a detail page health:<detail>, the
--     column titles and the function listing the rows; rows may
--     return nil, which hides the check
--   report: the field of utilities.mcpReport() that is the count;
--     the detail is the report page itself
-----------------------------------------------------------------------
utilities.checks = {
	{ title = "MCP scan: findings", report = "findings" },
	{ title = "Conflicts", detail = "conflicts", columns = { "Page", "Kind" }, rows = utilities.conflicts },
	{ title = "Aspiring pages", detail = "aspiring", columns = { "Missing page", "Linked from" }, rows = utilities.aspiring },
	{ title = "Invalid frontmatter", detail = "frontmatter", columns = { "Page", "Tag", "Error" }, rows = utilities.invalidFrontmatter },
	{ title = "Decisions proposed", detail = "decisions", columns = { "Decision", "id", "date" }, rows = utilities.decisionsProposed },
	{ title = "Decisions due for review", detail = "decisions", columns = { "Decision", "id", "last reviewed" }, rows = utilities.decisionsDue },
	{ title = "Tasks overdue", detail = "tasks", columns = { "Task", "Due", "Page" }, rows = utilities.tasksOverdue },
	{ title = "Tasks without due date", detail = "tasks", columns = { "Task", "Column", "Page" }, rows = utilities.tasksWithoutDue },
	{ title = "Pages waiting for review", detail = "proposed", columns = { "Page", "Proposed since" }, rows = utilities.waitingForReview },
	{ title = "MCP scan: files that are not pages", report = "files" }
}

-----------------------------------------------------------------------
-- utilities.health()
--
-- The health table: ${utilities.health()}.
--
-- One row per check: its title, linking to its detail, and its count.
-- The MCP rows say "no report" when the report page is missing, and
-- the findings row says when rendering is blocked.
--
-- Returns:
--   A markdown block widget.
-----------------------------------------------------------------------
function utilities.health()
	local report = utilities.mcpReport()
	local mcpLink = utilities.link(utilities.config().mcpPage)
	local rows = {}
	for _, check in ipairs(utilities.checks) do
		if check.report then
			local count = "no report"
			if report then
				count = tostring(report[check.report] or "?")
				if check.report == "findings" and report.blocked then
					count = count .. ", rendering blocked"
				end
			end
			table.insert(rows, { check.title, count, mcpLink })
		else
			local found = check.rows()
			if found then
				table.insert(rows, { check.title, tostring(#found), "[[health:" .. check.detail .. "]]" })
			end
		end
	end
	return widget.markdownBlock(utilities.table({ "Check", "Count", "Detail" }, rows))
end

-----------------------------------------------------------------------
-- utilities.healthPage(detail)
--
-- The markdown of the virtual page health:<detail>: one section per
-- check with that detail, each a table of its rows.
-----------------------------------------------------------------------
function utilities.healthPage(detail)
	local parts = {}
	for _, check in ipairs(utilities.checks) do
		if check.detail == detail then
			local found = check.rows()
			if found then
				table.insert(parts, "## " .. check.title .. " (" .. #found .. ")\n\n" .. utilities.table(check.columns, found))
			end
		end
	end
	if #parts == 0 then
		return "# Health\n\nNo such check: " .. utilities.code(detail) .. "\n"
	end
	return "# Health: " .. detail .. "\n\n" .. table.concat(parts, "\n\n") .. "\n"
end

-----------------------------------------------------------------------
-- Virtual page: the detail of a health check
--
-- Pattern: health:<detail>, e.g. health:aspiring
-----------------------------------------------------------------------
virtualPage.define {
	pattern = "health:(.+)",
	run = function(detail)
		return utilities.healthPage(detail)
	end
}
