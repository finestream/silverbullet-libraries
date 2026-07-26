-----------------------------------------------------------------------
-- Package library
-- 
-- reusable functions for silverbullet
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
-- Escape < and > 
-- currently it seems that there is no way to escape hence it is removed 
-----------------------------------------------------------------------
function library.escapePattern(s)
	return (s:gsub("[<>]",""))
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
			frontmatter = frontmatter:gsub("\n" .. key .. ":%s*.-\n", "\n" .. key .. ": " .. tostring(value) .. "\n", 1)
		else
			frontmatter = frontmatter:gsub("\n%-%-%-\n?$", "\n" .. key .. ": " .. tostring(value) .. "\n---\n")
		end
		editor.setText(frontmatter .. text:sub(fmEnd + 1))
		return true, value
	end

    -- No frontmatter: create one
	local newFrontmatter = "---\n" .. key .. ": " .. tostring(value) .. "\n" .. "---\n\n"
	editor.setText(newFrontmatter .. text)
	return true, value
end

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
function library.currentSubtree()
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
			finish = # text + 1,
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
function library.currentTask()
	local cursor = editor.getCursor()
	local currpage = editor.getCurrentPage()
	local tasks = query[[
        from index.tasks()
        where page == currpage
            and pos <= cursor
            and toPos >= cursor
    ]]
	if # tasks ~= 1 then
		editor.flashNotification("Expected exactly one task, found " .. # tasks .. ".", "error")
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
command.define{
	name = "refileSubtree",
	run = function()
		local subtree = library.currentSubtree()
		if not subtree then
			editor.flashNotification("No subtree found.", "error")
			return
		end
		local page = editor.prompt("Move subtree to page:", "Project/New project " .. os.date("%Y-%m-%d"))
		local ok, err = library.createPageWithText(page, subtree.text)
		if not ok then
			editor.flashNotification(err, "error")
			return
		end
		local text = editor.getText()
		local _, headingEnd = text:find("\n", subtree.start, true)
		if not headingEnd then
			headingEnd = # text
		end
		editor.replaceRange(
      headingEnd - 1, subtree.finish - 1, "\nMoved to: [[" .. page .. "]]")
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
slashCommand.define{
	name = "Idea: New",
	run = function()
		text = string.format("## |^|\n[created: %s]", os.date("%Y-%m-%d %H:%M"))
		editor.insertAtCursor(text, false, true)
	end
}

-----------------------------------------------------------------------
-- Command: add page id
-----------------------------------------------------------------------
command.define{
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
-- Get page by pageId
-----------------------------------------------------------------------
virtualPage.define{
	pattern = "pageId:(.+)",
	run = function(tgtpageId)
		local pages = query[[
            from index.pages()
            where pageId == tgtpageId
        ]]
		if # pages == 0 then
			return "# Page not found\n\nNo page with pageId `" .. tgtpageId .. "`."
		end
		if # pages > 1 then
			return "# Duplicate pageId\n\nMore than one page has pageId `" .. tgtpageId .. "`.\n"
		end
		local pageName = pages[1].name
		return "# Page with PageId " .. tgtpageId .. "\n\nRedirecting... if the redirect does not work click here:  [[" .. pageName .. "]] .. ${editor.navigate(\"" .. pageName .. "@1\")}\n"
	end
}