
-----------------------------------------------------------------------
-- Kanboard.views
--
-- What pages call. A page calls Kanboard.views.* only, so a space that
-- restricts what its pages may call needs nothing else of this library
-- on its allowlist.
--
-- Everything a view receives is data. Text that comes from a task, a
-- page name or a column list reaches the page as a DOM text node or as
-- an attribute value, never as HTML or markdown: the Std `dom` API
-- renders a string child as markdown, so the views never pass one and
-- build their nodes with Kanboard.views.node instead.
-----------------------------------------------------------------------
Kanboard.views = {}

-----------------------------------------------------------------------
-- Kanboard.views.defaults
--
-- Fallback values of the `taskTable` section of the "kanboard"
-- configuration:
--   open, done        - text of the button of an open and of a done task
--   boxSize           - font size of that button, a CSS length
--   emptyAttribute    - shown for an attribute a task does not have
--   defaultAttributes - the columns after Task and Page when the page
--                       passes none: { header, attribute, format }
-----------------------------------------------------------------------
Kanboard.views.defaults = {
	open = "☐",
	done = "☑",
	boxSize = "1.4em",
	emptyAttribute = "---",
	defaultAttributes = {
		{ "Project", "project", "string" },
		{ "Category", "category", "string" },
		{ "Due Date", "due", "date" },
		{ "Swimlane", "swimlane", "string" },
		{ "Column", "column", "string" }
	}
}

-----------------------------------------------------------------------
-- Kanboard.views.state
--
-- Search text, sort order, filters and open filter list of every
-- rendered task table, keyed by page, columns and tasks.
--
-- SilverBullet re-renders widgets while the page is being edited.
-- Remembering the settings here keeps such a re-render from resetting
-- the table the reader has just sorted or filtered.
-----------------------------------------------------------------------
Kanboard.views.state = {}

-----------------------------------------------------------------------
-- Kanboard.views.config()
--
-- Reads the `taskTable` section of the "kanboard" configuration.
--
-- Returns:
--   Table with open, done, boxSize, emptyAttribute and
--   defaultAttributes, where every value the user did not configure is
--   taken from Kanboard.views.defaults.
-----------------------------------------------------------------------
function Kanboard.views.config()
	local effective = {}
	for key, value in pairs(Kanboard.views.defaults) do
		effective[key] = value
	end
	local set = (config.get("kanboard") or {}).taskTable
	if type(set) == "table" then
		for key, value in pairs(set) do
			if value ~= nil and value ~= "" then
				effective[key] = value
			end
		end
	end
	return effective
end

-----------------------------------------------------------------------
-- Kanboard.views.cssSize(value, fallback)
--
-- Accepts a CSS length such as "1.8em" or "24px".
--
-- Returns:
--   value, or fallback when value is anything but a number followed by
--   a unit, so that nothing else can reach a style.
-----------------------------------------------------------------------
function Kanboard.views.cssSize(value, fallback)
	if type(value) == "string" and value:match("^%d*%.?%d+[%a%%]+$") then
		return value
	end
	return fallback
end

-----------------------------------------------------------------------
-- Kanboard.views.columns(columns)
--
-- Normalizes a column list as pages and the configuration write it:
--   { { "Due Date", "due", "date" }, { "Column", "column" } }
--
-- Returns:
--   Array of { header, key, format }. An entry without an attribute
--   name is dropped; the header defaults to the attribute name and the
--   format to "string". Anything that is not a list yields {}; an empty
--   list of the configuration arrives as an empty object and yields {}
--   as well.
-----------------------------------------------------------------------
function Kanboard.views.columns(columns)
	local list = {}
	if type(columns) ~= "table" then
		return list
	end
	for _, column in ipairs(columns) do
		if type(column) == "table" and type(column[2]) == "string" and column[2] ~= "" then
			local format = column[3]
			if type(format) ~= "string" or format == "" then
				format = "string"
			end
			table.insert(list, {
				header = tostring(column[1] or column[2]),
				key = column[2],
				format = format
			})
		end
	end
	return list
end

-----------------------------------------------------------------------
-- Kanboard.views.format(value, format, raw)
--
-- Formats an attribute value for display.
--
-- format:
--   "string"    the value as it is; a list is joined with ", "
--   "date"      YYYY-MM-DD
--   "dateTime"  YYYY-MM-DD hh:mm
--   a pattern   any text holding YYYY, YY, MM, DD, hh or mm, for
--               example "DD.MM.YY"
--
-- raw is the value of the attribute's `<name>Raw` companion, if the
-- task has one: Kanboard reports "no date" as 0, which the cache holds
-- as 1970-01-01, so a raw value of 0 means the date is not set.
--
-- Returns:
--   The text to show, or nil when there is nothing to show. A value of
--   a date format that holds no date is returned unchanged.
--
-- Each substitution is its own statement: gsub returns two values, and
-- Space Lua cannot call a method on a multi-value result.
-----------------------------------------------------------------------
function Kanboard.views.format(value, format, raw)
	if value == nil or value == "" then
		return nil
	end
	if type(value) == "table" then
		local parts = {}
		for _, part in ipairs(value) do
			table.insert(parts, tostring(part))
		end
		if #parts == 0 then
			return nil
		end
		return table.concat(parts, ", ")
	end
	local text = tostring(value)
	if format == "string" then
		return text
	end
	if raw ~= nil and tonumber(raw) == 0 then
		return nil
	end
	local year, month, day = text:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if year == nil then
		return text
	end
	local hour, minute = text:match("%d%d%d%d%-%d%d%-%d%d[T ](%d%d):(%d%d)")
	hour = hour or "00"
	minute = minute or "00"
	if format == "date" then
		return year .. "-" .. month .. "-" .. day
	end
	if format == "dateTime" then
		return year .. "-" .. month .. "-" .. day .. " " .. hour .. ":" .. minute
	end
	local isPattern = format:find("YY", 1, true) or format:find("MM", 1, true)
		or format:find("DD", 1, true) or format:find("hh", 1, true)
		or format:find("mm", 1, true)
	if not isPattern then
		return text
	end
	local formatted = format
	formatted = formatted:gsub("YYYY", year)
	formatted = formatted:gsub("YY", year:sub(3, 4))
	formatted = formatted:gsub("MM", month)
	formatted = formatted:gsub("DD", day)
	formatted = formatted:gsub("hh", hour)
	formatted = formatted:gsub("mm", minute)
	return formatted
end

-----------------------------------------------------------------------
-- Kanboard.views.node(tag, attributes, text)
--
-- Builds a DOM node whose content is plain text.
--
-- attributes are set with setAttribute, and a key starting with "on"
-- is added as an event listener (the Std `dom` API). text becomes a
-- text node, so markup in it is shown, not interpreted.
--
-- Returns:
--   DOM node
-----------------------------------------------------------------------
function Kanboard.views.node(tag, attributes, text)
	local node = dom[tag](attributes or {})
	if text ~= nil then
		node.appendChild(js.window.document.createTextNode(tostring(text)))
	end
	return node
end

-----------------------------------------------------------------------
-- Kanboard.views.pageLink(ref, label)
--
-- Builds a link to a page of the space, or to a position on it
-- ("Page@123").
--
-- A plain click navigates inside the client; with Ctrl or Cmd held the
-- browser follows the href. The href starts with "./", so whatever the
-- reference holds ("javascript:...", "//host/...") it stays a path
-- under the client's base URL.
--
-- Returns:
--   DOM node
-----------------------------------------------------------------------
function Kanboard.views.pageLink(ref, label)
	return Kanboard.views.node("a", {
		class = "kanboard-tasks-link",
		href = "./" .. js.window.encodeURI(ref),
		title = ref,
		onclick = function(event)
			if event.ctrlKey or event.metaKey then
				return
			end
			event.preventDefault()
			editor.navigate(ref)
		end
	}, label)
end

-----------------------------------------------------------------------
-- Kanboard.views.inline(parent, text)
--
-- Appends a task text to parent, with its links.
--
-- Three things become links, everything else is plain text:
--   [[Page]] and [[Page|alias]]   a link to the page
--   [label](url)                  an external link
--   a bare http(s) URL            an external link
--
-- An external link is made only for an http, https or mailto URL; a
-- markdown link with any other scheme (javascript:, data:) is shown as
-- the text it was written as.
-----------------------------------------------------------------------
function Kanboard.views.inline(parent, text)
	local node = Kanboard.views.node
	local function plain(part)
		if part ~= "" then
			parent.appendChild(js.window.document.createTextNode(part))
		end
	end
	local function external(url, label)
		parent.appendChild(node("a", {
			class = "kanboard-tasks-link",
			href = url,
			target = "_blank",
			rel = "noopener noreferrer"
		}, label))
	end

	local position = 1
	while position <= #text do
		local wikiStart, wikiEnd, wikiTarget = text:find("%[%[([^%[%]\n]+)%]%]", position)
		local linkStart, linkEnd, linkLabel, linkUrl =
			text:find("%[([^%[%]\n]*)%]%(([^%s%(%)]+)%)", position)
		local urlStart, urlEnd = text:find("https?://[^%s<>\"'%(%)%[%]]+", position)

		local first = wikiStart
		if linkStart ~= nil and (first == nil or linkStart < first) then
			first = linkStart
		end
		if urlStart ~= nil and (first == nil or urlStart < first) then
			first = urlStart
		end
		if first == nil then
			break
		end
		plain(text:sub(position, first - 1))

		if first == wikiStart then
			local ref, alias = wikiTarget:match("^([^|]*)|(.*)$")
			if ref == nil then
				ref = wikiTarget
			end
			if alias == nil or alias == "" then
				alias = ref
			end
			if ref == "" then
				plain(text:sub(wikiStart, wikiEnd))
			else
				parent.appendChild(Kanboard.views.pageLink(ref, alias))
			end
			position = wikiEnd + 1
		elseif first == linkStart then
			local scheme = linkUrl:lower()
			if scheme:match("^https?://") or scheme:match("^mailto:") then
				if linkLabel == "" then
					linkLabel = linkUrl
				end
				external(linkUrl, linkLabel)
			else
				plain(text:sub(linkStart, linkEnd))
			end
			position = linkEnd + 1
		else
			local url = text:sub(urlStart, urlEnd)
			external(url, url)
			position = urlEnd + 1
		end
	end
	plain(text:sub(position))
end

-----------------------------------------------------------------------
-- Kanboard.views.pagesById(rows)
--
-- Maps the pageId of every page of the space to its name, to show the
-- page a Kanboard task was sent from (the task's `pageId`).
--
-- Returns:
--   Table pageId -> page name; {} without a query when no row has a
--   pageId.
-----------------------------------------------------------------------
function Kanboard.views.pagesById(rows)
	local wanted = false
	for _, task in ipairs(rows) do
		if type(task) == "table" and task.pageId ~= nil and task.pageId ~= "" then
			wanted = true
		end
	end
	local pages = {}
	if not wanted then
		return pages
	end
	local found = query [[from p = index.pages() where p.pageId ~= nil]]
	for _, page in ipairs(found or {}) do
		local id = tostring(page.pageId)
		if pages[id] == nil then
			pages[id] = page.name
		end
	end
	return pages
end

-----------------------------------------------------------------------
-- Kanboard.views.toggle(task, state)
--
-- Toggles a task between open and done, where it is written.
--
-- input: task:  a row as the view received it (page, pos, name)
--        state: the state the table shows for it (" ", "x", ...)
--
-- Workflow:
--   1. Find the task in the index by page and position; it must be
--      there under the name the table shows. A row made up by a page,
--      or a table older than the last change of the task's page, ends
--      here.
--   2. Read the text of that page (the editor's, when it is the open
--      page) and check that the task marker with the shown state is at
--      that position.
--   3. Let SilverBullet change the marker (index.updateTaskState, what
--      a click on the checkbox of a task does).
--
-- So a click changes the state marker of an existing task and nothing
-- else. A task of the Kanboard cache marked done this way reaches
-- Kanboard with the next `Kanboard: Update Cache`, as one ticked in
-- the cache page does (Kanboard.closeTasks).
--
-- Returns:
--   The new state ("x" or " "), or nil when nothing was changed.
-----------------------------------------------------------------------
function Kanboard.views.toggle(task, state)
	local page = task.page
	local position = tonumber(task.pos)
	if type(page) ~= "string" or page == "" or position == nil then
		return nil
	end
	local outdated = "Kanboard: this task has changed since the table was shown. Reload the page."

	-- 1. Find the task in the index.
	local found = query [[from t = index.tasks() where t.page == page and t.pos == position]]
	if found == nil or #found ~= 1 or found[1].name ~= task.name then
		Library.notify(Library.ERROR, outdated)
		return nil
	end

	-- 2. Check the task marker in the text of the page.
	local text
	if editor.getCurrentPage() == page then
		text = editor.getText()
	else
		text = space.readPage(page)
	end
	local marker = text:sub(position + 1, position + 3)
	local written = text:sub(position + 4, position + 3 + #state)
	local closing = text:sub(position + 4 + #state, position + 4 + #state)
	if not marker:match("^[%*%-%+] %[$") or written ~= state or closing ~= "]" then
		Library.notify(Library.ERROR, outdated)
		return nil
	end

	-- 3. Let SilverBullet change the marker.
	local newState = "x"
	if state == "x" or state == "X" then
		newState = " "
	end
	system.invokeFunction("index.updateTaskState", page .. "@" .. tostring(position), state, newState)
	if newState == "x" then
		Library.notify(Library.INFO, "Kanboard: task marked done.")
	else
		Library.notify(Library.INFO, "Kanboard: task reopened.")
	end
	return newState
end

-----------------------------------------------------------------------
-- Kanboard.views.funnel()
--
-- The icon of the filter buttons, drawn as an inline SVG.
--
-- Returns:
--   DOM node
-----------------------------------------------------------------------
function Kanboard.views.funnel()
	local namespace = "http://www.w3.org/2000/svg"
	local svg = js.window.document.createElementNS(namespace, "svg")
	svg.setAttribute("viewBox", "0 0 24 24")
	svg.setAttribute("width", "1em")
	svg.setAttribute("height", "1em")
	svg.setAttribute("fill", "none")
	svg.setAttribute("stroke", "currentColor")
	svg.setAttribute("stroke-width", "2")
	svg.setAttribute("stroke-linejoin", "round")
	svg.setAttribute("aria-hidden", "true")
	local path = js.window.document.createElementNS(namespace, "path")
	path.setAttribute("d", "M3 4h18l-7 9v6l-4 2v-8z")
	svg.appendChild(path)
	return svg
end

-----------------------------------------------------------------------
-- Kanboard.views.tasks(rows, columns)
--
-- Renders tasks as a table: a button to mark a task done or open, the
-- task text with its links, the page, and one column per attribute.
-- This is the function a page calls:
--
--   ${Kanboard.views.tasks(query[[from t = index.tasks()
--     where t.column == "Ready"]])}
--
-- input: rows:    tasks, as a query over index.tasks() returns them
--        columns: optional list of { header, attribute, format } (see
--                 Kanboard.views.columns and Kanboard.views.format);
--                 the `defaultAttributes` of the configuration when
--                 omitted
--
-- Above the table: a search field over all columns, the number of
-- tasks shown, and a reset button. In the header: a click on a column
-- name sorts by it (ascending, descending, back to the order of the
-- rows), the funnel opens the list of that column's values to filter
-- by.
--
-- The Page column shows the page a task was sent to Kanboard from
-- (its `pageId`), and otherwise the page the task is written on.
--
-- Sorting, searching and filtering happen in the browser: the rows are
-- built once, then reordered and hidden. The table is made of div
-- elements laid out as a table, not of a <table>, so that a library
-- that decorates every table of the client leaves it alone.
--
-- Returns:
--   A block widget.
-----------------------------------------------------------------------
function Kanboard.views.tasks(rows, columns)
	local cfg = Kanboard.views.config()
	local node = Kanboard.views.node
	local openText = tostring(cfg.open)
	local doneText = tostring(cfg.done)
	local emptyText = tostring(cfg.emptyAttribute)
	local boxSize = Kanboard.views.cssSize(cfg.boxSize, Kanboard.views.defaults.boxSize)
	if type(rows) ~= "table" then
		rows = {}
	end
	if columns == nil then
		columns = cfg.defaultAttributes
	end
	local attributes = Kanboard.views.columns(columns)
	local pages = Kanboard.views.pagesById(rows)

	-- The columns of the table: state, task, page, then the attributes.
	local heads = {
		{ header = "", class = "kanboard-tasks-state", filter = true },
		{ header = "Task", class = "kanboard-tasks-task", filter = false },
		{ header = "Page", class = "kanboard-tasks-page", filter = true }
	}
	local columnKeys = {}
	for _, attribute in ipairs(attributes) do
		table.insert(heads, { header = attribute.header, class = "kanboard-tasks-attribute", filter = true })
		table.insert(columnKeys, attribute.key .. ":" .. attribute.format)
	end

	-------------------------------------------------------------------
	-- One record per task: what each column shows (values, also what
	-- the filters and the search compare) and what it sorts by (keys).
	-------------------------------------------------------------------
	local records = {}
	local signature = {}
	for index, task in ipairs(rows) do
		if type(task) == "table" then
			local record = { task = task, index = index, values = {}, keys = {} }
			record.state = task.state
			if type(record.state) ~= "string" then
				record.state = " "
			end
			record.done = task.done == true or record.state == "x" or record.state == "X"
			record.name = tostring(task.name or task.text or "")
			record.values[2] = record.name
			record.keys[2] = record.name:lower()

			local sentFrom = nil
			if task.pageId ~= nil then
				sentFrom = pages[tostring(task.pageId)]
			end
			if sentFrom ~= nil then
				record.pageRef = sentFrom
				record.pageName = sentFrom
			elseif type(task.page) == "string" and task.page ~= "" then
				record.pageName = task.page
				record.pageRef = task.page
				if tonumber(task.pos) ~= nil then
					record.pageRef = task.page .. "@" .. tostring(tonumber(task.pos))
				end
			end
			if record.pageName ~= nil then
				record.values[3] = record.pageName:match("([^/]+)$") or record.pageName
				record.keys[3] = record.values[3]:lower()
			else
				record.values[3] = ""
			end

			for offset, attribute in ipairs(attributes) do
				local shown = Kanboard.views.format(task[attribute.key], attribute.format,
					task[attribute.key .. "Raw"])
				if shown == nil or shown == "" then
					record.values[3 + offset] = ""
				else
					record.values[3 + offset] = shown
					if attribute.format == "string" or type(task[attribute.key]) == "table" then
						record.keys[3 + offset] = shown:lower()
					else
						record.keys[3 + offset] = tostring(task[attribute.key])
					end
				end
			end
			table.insert(records, record)
			table.insert(signature, tostring(task.ref or task.kbId or record.name))
		end
	end

	-- A column whose values are all numbers sorts as numbers.
	for column = 4, #heads do
		local numeric = true
		for _, record in ipairs(records) do
			if record.keys[column] ~= nil and tonumber(record.values[column]) == nil then
				numeric = false
			end
		end
		if numeric then
			for _, record in ipairs(records) do
				if record.keys[column] ~= nil then
					record.keys[column] = tonumber(record.values[column])
				end
			end
		end
	end

	local key = tostring(editor.getCurrentPage()) .. "|" .. table.concat(columnKeys, ",") ..
		"|" .. table.concat(signature, ",")
	local state = Kanboard.views.state[key]
	if state == nil then
		state = { search = "", sort = nil, descending = false, excluded = {} }
		Kanboard.views.state[key] = state
	end

	-------------------------------------------------------------------
	-- The nodes.
	-------------------------------------------------------------------
	local container = node("div", { class = "kanboard-tasks" })
	local toolbar = node("div", { class = "kanboard-tasks-toolbar" })
	local searchField = node("input", {
		class = "kanboard-tasks-search",
		type = "search",
		placeholder = "Search",
		["aria-label"] = "Search tasks"
	})
	searchField.value = state.search
	local counter = node("span", { class = "kanboard-tasks-count" })
	local panel = node("div", { class = "kanboard-tasks-panel" })
	panel.style.display = "none"
	local grid = node("div", { class = "kanboard-tasks-table", role = "table" })
	local head = node("div", { class = "kanboard-tasks-head", role = "rowgroup" })
	local headRow = node("div", { class = "kanboard-tasks-row", role = "row" })
	local body = node("div", { class = "kanboard-tasks-body", role = "rowgroup" })
	local note = node("div", { class = "kanboard-tasks-note" })
	-- Cells, sort marks and filter buttons of the header, by column.
	local headCells = {}
	local sortMarks = {}
	local filterButtons = {}

	-- What a record shows in the state column, and how it sorts there.
	local function paint(record)
		if record.done then
			record.values[1] = "Done"
			record.keys[1] = 1
			record.node.classList.add("kanboard-tasks-done")
		else
			record.values[1] = "Open"
			record.keys[1] = 0
			record.node.classList.remove("kanboard-tasks-done")
		end
		record.button.textContent = record.done and doneText or openText
		if record.done then
			record.button.title = "Done. Click to reopen."
		else
			record.button.title = "Open. Click to mark done."
		end
		local parts = {}
		for column = 1, #heads do
			table.insert(parts, record.values[column])
		end
		record.haystack = table.concat(parts, "\n"):lower()
	end

	-- Hides the records the search and the filters exclude.
	local function apply()
		local needle = state.search:lower()
		local shown = 0
		for _, record in ipairs(records) do
			local visible = true
			if needle ~= "" then
				local at = record.haystack:find(needle, 1, true)
				visible = at ~= nil
			end
			for column, excluded in pairs(state.excluded) do
				if excluded[record.values[column]] then
					visible = false
				end
			end
			if visible then
				shown = shown + 1
				record.node.style.display = ""
				if shown % 2 == 0 then
					record.node.classList.add("kanboard-tasks-even")
				else
					record.node.classList.remove("kanboard-tasks-even")
				end
			else
				record.node.style.display = "none"
			end
		end
		local unit = "tasks"
		if #records == 1 then
			unit = "task"
		end
		if shown == #records then
			counter.textContent = string.format("%d %s", #records, unit)
		else
			counter.textContent = string.format("%d / %d %s", shown, #records, unit)
		end
		if #records == 0 then
			note.textContent = "No tasks."
		elseif shown == 0 then
			note.textContent = "No task matches the search and the filters."
		else
			note.textContent = ""
		end
		for column, button in pairs(filterButtons) do
			local active = false
			for _, _ in pairs(state.excluded[column] or {}) do
				active = true
			end
			if active then
				button.classList.add("kanboard-tasks-active")
			else
				button.classList.remove("kanboard-tasks-active")
			end
		end
	end

	-- Puts the records in the order of the sort column, then applies
	-- the search and the filters. A record without a value comes last
	-- in both directions; equal values keep the order of the rows.
	local function order()
		local sorted = {}
		for _, record in ipairs(records) do
			table.insert(sorted, record)
		end
		local column = state.sort
		if column ~= nil then
			table.sort(sorted, function(first, second)
				local firstKey, secondKey = first.keys[column], second.keys[column]
				if firstKey == nil or secondKey == nil then
					if firstKey == nil and secondKey == nil then
						return first.index < second.index
					end
					return secondKey == nil
				end
				if firstKey == secondKey then
					return first.index < second.index
				end
				if state.descending then
					return firstKey > secondKey
				end
				return firstKey < secondKey
			end)
		end
		for _, record in ipairs(sorted) do
			body.appendChild(record.node)
		end
		for index, mark in pairs(sortMarks) do
			if index ~= column then
				mark.textContent = ""
				headCells[index].setAttribute("aria-sort", "none")
			elseif state.descending then
				mark.textContent = "▼"
				headCells[index].setAttribute("aria-sort", "descending")
			else
				mark.textContent = "▲"
				headCells[index].setAttribute("aria-sort", "ascending")
			end
		end
		apply()
	end

	-- Lists the values of a column in the panel, each with a checkbox
	-- and the number of tasks that have it; nil closes the panel.
	local function showPanel(column)
		state.panel = column
		panel.replaceChildren()
		if column == nil then
			panel.style.display = "none"
			return
		end
		panel.style.display = ""

		local counts = {}
		local values = {}
		for _, record in ipairs(records) do
			local value = record.values[column]
			if counts[value] == nil then
				counts[value] = 0
				table.insert(values, value)
			end
			counts[value] = counts[value] + 1
		end
		table.sort(values, function(first, second)
			return first:lower() < second:lower()
		end)

		local title = heads[column].header
		if title == "" then
			title = "State"
		end
		panel.appendChild(node("span", { class = "kanboard-tasks-panel-title" }, "Filter " .. title .. ":"))
		local boxes = {}
		for _, value in ipairs(values) do
			local label = node("label", { class = "kanboard-tasks-choice" })
			local box = node("input", { type = "checkbox" })
			box.checked = not (state.excluded[column] or {})[value]
			box.addEventListener("change", function()
				local excluded = state.excluded[column] or {}
				if box.checked then
					excluded[value] = nil
				else
					excluded[value] = true
				end
				state.excluded[column] = excluded
				apply()
			end)
			boxes[value] = box
			label.appendChild(box)
			local shown = value
			if shown == "" then
				shown = emptyText
			end
			label.appendChild(js.window.document.createTextNode(
				string.format(" %s (%d)", shown, counts[value])))
			panel.appendChild(label)
		end
		local function setAll(checked)
			local excluded = {}
			for value, box in pairs(boxes) do
				box.checked = checked
				if not checked then
					excluded[value] = true
				end
			end
			state.excluded[column] = excluded
			apply()
		end
		panel.appendChild(node("button", {
			type = "button",
			class = "kanboard-tasks-button",
			onclick = function() setAll(true) end
		}, "All"))
		panel.appendChild(node("button", {
			type = "button",
			class = "kanboard-tasks-button",
			onclick = function() setAll(false) end
		}, "None"))
		panel.appendChild(node("button", {
			type = "button",
			class = "kanboard-tasks-button",
			onclick = function() showPanel(nil) end
		}, "Close"))
	end

	-- The toolbar.
	searchField.addEventListener("input", function()
		state.search = tostring(searchField.value or "")
		apply()
	end)
	toolbar.appendChild(searchField)
	toolbar.appendChild(counter)
	toolbar.appendChild(node("button", {
		type = "button",
		class = "kanboard-tasks-button kanboard-tasks-reset",
		title = "Reset the search, the sorting and the filters",
		onclick = function()
			state.search = ""
			state.sort = nil
			state.descending = false
			state.excluded = {}
			searchField.value = ""
			showPanel(nil)
			order()
		end
	}, "Reset"))

	-- The header.
	for column, spec in ipairs(heads) do
		local cell = node("div", { class = "kanboard-tasks-cell " .. spec.class, role = "columnheader" })
		local heading = node("span", { class = "kanboard-tasks-heading" })
		headCells[column] = cell
		if spec.filter then
			local filterButton = node("button", {
				type = "button",
				class = "kanboard-tasks-filter",
				title = "Filter by this column",
				onclick = function()
					if state.panel == column then
						showPanel(nil)
					else
						showPanel(column)
					end
				end
			})
			filterButton.appendChild(Kanboard.views.funnel())
			filterButtons[column] = filterButton
			heading.appendChild(filterButton)
		end
		local sortButton = node("button", {
			type = "button",
			class = "kanboard-tasks-sort",
			title = "Sort by this column",
			onclick = function()
				if state.sort ~= column then
					state.sort = column
					state.descending = false
				elseif not state.descending then
					state.descending = true
				else
					state.sort = nil
					state.descending = false
				end
				order()
			end
		}, spec.header)
		local mark = node("span", { class = "kanboard-tasks-mark", ["aria-hidden"] = "true" })
		sortMarks[column] = mark
		sortButton.appendChild(mark)
		heading.appendChild(sortButton)
		cell.appendChild(heading)
		headRow.appendChild(cell)
	end

	-- The rows.
	for _, record in ipairs(records) do
		local task = record.task
		local row = node("div", { class = "kanboard-tasks-row", role = "row" })
		record.node = row

		local stateCell = node("div", { class = "kanboard-tasks-cell kanboard-tasks-state", role = "cell" })
		record.button = node("button", { type = "button", class = "kanboard-tasks-toggle" })
		record.button.style.fontSize = boxSize
		if type(task.page) == "string" and tonumber(task.pos) ~= nil then
			record.button.addEventListener("click", function()
				local newState = Kanboard.views.toggle(task, record.state)
				if newState == nil then
					return
				end
				record.state = newState
				record.done = newState == "x"
				paint(record)
				if state.panel == 1 then
					showPanel(1)
				end
				apply()
			end)
		else
			record.button.disabled = true
		end
		stateCell.appendChild(record.button)
		row.appendChild(stateCell)

		local taskCell = node("div", { class = "kanboard-tasks-cell kanboard-tasks-task", role = "cell" })
		Kanboard.views.inline(taskCell, record.name)
		row.appendChild(taskCell)

		local pageCell = node("div", { class = "kanboard-tasks-cell kanboard-tasks-page", role = "cell" })
		if record.pageRef ~= nil then
			local link = Kanboard.views.pageLink(record.pageRef, record.values[3])
			link.title = record.pageName
			pageCell.appendChild(link)
		end
		row.appendChild(pageCell)

		for offset, attribute in ipairs(attributes) do
			local value = record.values[3 + offset]
			local class = "kanboard-tasks-cell kanboard-tasks-attribute"
			if value == "" then
				class = class .. " kanboard-tasks-empty"
				value = emptyText
			elseif attribute.format ~= "string" then
				class = class .. " kanboard-tasks-date"
			end
			row.appendChild(node("div", { class = class, role = "cell" }, value))
		end
		paint(record)
	end

	head.appendChild(headRow)
	grid.appendChild(head)
	grid.appendChild(body)
	container.appendChild(toolbar)
	container.appendChild(panel)
	container.appendChild(grid)
	container.appendChild(note)
	order()
	if state.panel ~= nil and heads[state.panel] ~= nil and heads[state.panel].filter then
		showPanel(state.panel)
	end

	-- No "markdown" key here on purpose: SilverBullet 2.9 renders it
	-- *instead of* "html".
	return widget.new {
		html = container,
		display = "block"
	}
end
