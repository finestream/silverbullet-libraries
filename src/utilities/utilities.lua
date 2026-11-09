-----------------------------------------------------------------------
-- Package utilities
--
-- Space-wide views that belong to no other library: the tag cloud and
-- the health table (health.lua). Pages call utilities.tagCloud() and
-- utilities.health() only.
--
-- Everything is computed from the index when a page is shown; nothing
-- is stored. Text that comes from the space (page names, tag names,
-- frontmatter values, error messages) is never written into markdown
-- as is: page names become links only when they cannot break out of
-- one, everything else goes into a code span (utilities.code).
-----------------------------------------------------------------------
utilities = utilities or {}

-----------------------------------------------------------------------
-- utilities.defaults
--
-- Fallback values for the "utilities" section of the CONFIG page.
-- proposedPrefix has no default: the check it drives is shown only
-- once a folder is configured.
-----------------------------------------------------------------------
utilities.defaults = {
	exclude = { "Library/" },  -- pages left out of every view
	mcpPage = "MCP Server",    -- report page of the MCP server's scan
	proposedPrefix = nil,      -- folder of pages waiting for review; nil: no check
	proposedDays = 7           -- days a page may wait in `proposed`
}

-----------------------------------------------------------------------
-- utilities.config()
--
-- Reads the "utilities" section of the CONFIG page.
--
-- Returns:
--   Table with the configured values, and the defaults for every key
--   the user did not configure.
-----------------------------------------------------------------------
function utilities.config()
	local effective = {}
	for key, value in pairs(utilities.defaults) do effective[key] = value end
	for key, value in pairs(config.get("utilities", {}) or {}) do effective[key] = value end
	return effective
end

-----------------------------------------------------------------------
-- utilities.excluded(name)
--
-- Whether a page (or document) name starts with one of the configured
-- `exclude` prefixes.
-----------------------------------------------------------------------
function utilities.excluded(name)
	for _, prefix in ipairs(utilities.config().exclude or {}) do
		if string.startsWith(name, prefix) then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- utilities.safeName(name)
--
-- Whether a name can be written into a wiki link or a tag link as is:
-- no brackets, pipes, braces, dollars, angle brackets, backticks or
-- line breaks, which could end the link or start a directive or HTML,
-- and no leading URL scheme ("javascript:"), which could turn the link
-- into something other than a page.
-----------------------------------------------------------------------
function utilities.safeName(name)
	if type(name) ~= "string" or name == "" then return false end
	if string.find(name, "^%a[%w+-]*:") then return false end
	return string.find(name, "[%[%]|{}%$<>`\r\n]") == nil
end

-----------------------------------------------------------------------
-- utilities.code(text)
--
-- Any value as an inert markdown code span, fit for a table cell.
--
-- The fence is one backtick longer than the longest run of backticks
-- in the text, line breaks become spaces and pipes are escaped, so
-- the text can neither end the span nor the table cell. Inside a code
-- span SilverBullet evaluates no directive and renders no HTML.
--
-- Returns:
--   The code span, or "" for nil and the empty string.
-----------------------------------------------------------------------
function utilities.code(text)
	if text == nil then return "" end
	local flat = string.gsub(tostring(text), "[\r\n]+", " ")
	if flat == "" then return "" end
	local longest = 0
	for run in string.gmatch(flat, "`+") do
		if #run > longest then longest = #run end
	end
	local fence = string.rep("`", longest + 1)
	local escaped = string.gsub(flat, "|", "\\|")
	return fence .. " " .. escaped .. " " .. fence
end

-----------------------------------------------------------------------
-- utilities.link(name)
--
-- A page name as a wiki link when that is safe, as a code span
-- otherwise.
-----------------------------------------------------------------------
function utilities.link(name)
	if utilities.safeName(name) then return "[[" .. name .. "]]" end
	return utilities.code(name)
end

-----------------------------------------------------------------------
-- utilities.table(columns, rows)
--
-- A markdown table. Cells must already be markdown (utilities.code,
-- utilities.link or numbers).
--
-- Returns:
--   The table, or "*None.*" when there are no rows.
-----------------------------------------------------------------------
function utilities.table(columns, rows)
	if #rows == 0 then return "*None.*" end
	local lines = {
		"| " .. table.concat(columns, " | ") .. " |",
		"|" .. string.rep(" --- |", #columns)
	}
	for _, row in ipairs(rows) do
		local cells = {}
		for i = 1, #columns do
			local value = row[i]
			if value == nil then value = "" end
			table.insert(cells, tostring(value))
		end
		table.insert(lines, "| " .. table.concat(cells, " | ") .. " |")
	end
	return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- utilities.today()
--
-- Today's date as "YYYY-MM-DD", for comparing with frontmatter dates.
-----------------------------------------------------------------------
function utilities.today()
	return os.date("%Y-%m-%d")
end

-----------------------------------------------------------------------
-- utilities.daysAgo(days)
--
-- The date `days` days before today as "YYYY-MM-DD".
-----------------------------------------------------------------------
function utilities.daysAgo(days)
	return os.date("%Y-%m-%d", os.time() - days * 86400)
end

-----------------------------------------------------------------------
-- utilities.day(value)
--
-- The "YYYY-MM-DD" part of a date or timestamp value, or nil.
-----------------------------------------------------------------------
function utilities.day(value)
	if value == nil then return nil end
	return string.match(tostring(value), "^(%d%d%d%d%-%d%d%-%d%d)")
end

-----------------------------------------------------------------------
-- utilities.tagCloud()
--
-- Every tag of the space once, alphabetically, as tag links
-- ([[tag:x|#x]]) separated by spaces, for inline use on a page:
-- ${utilities.tagCloud()}.
--
-- Left out: tags starting with "meta", tags that occur only on pages
-- matching the `exclude` prefixes, and tags whose name could break the
-- link (utilities.safeName).
--
-- Returns:
--   The links as one markdown string ("" when there is no tag).
-----------------------------------------------------------------------
function utilities.tagCloud()
	local seen, out = {}, {}
	local tags = query[[from t = index.tag "tag" order by t.name]]
	for _, t in ipairs(tags) do
		if not seen[t.name]
			and not string.startsWith(t.name, "meta")
			and not utilities.excluded(t.page)
			and utilities.safeName(t.name) then
			seen[t.name] = true
			table.insert(out, "[[tag:" .. t.name .. "|#" .. t.name .. "]]")
		end
	end
	return table.concat(out, " ")
end
