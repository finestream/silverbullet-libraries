-----------------------------------------------------------------------
-- utilities.remark()
--
-- Adds a comment like SilverBullet's own "Comment: Add" does (after the
-- current block, indented inside a list item, the selection quoted) and
-- starts it with the moment and the author:
--
--   <!--
--   ${os.date("%d %B %Y, %H:%M", 1795000000)} -- @name
--
--   -->
--
-- The date line is the first line inside the comment, whatever the
-- built-in put there (a quoted selection follows it). The cursor stays
-- where the built-in left it, moved on by the date line: on the empty
-- line below it, or, with a selection, on the blank line after the
-- quote.
--
-- The moment is stored as seconds since the epoch, so the page keeps an
-- absolute time; os.date shows it in the time zone of the browser that
-- renders the page, so every reader sees it in their own. The name is
-- identity.own(), the logged-in user, as a signature (" -- @name"), which
-- does not address the author the way a bare @name would. Where the
-- space does not know the user, the line holds the moment only.
--
-- The built-in command stays as it is; this one runs it and then writes
-- the line into what it made.
--
-- Returns:
--   Nothing.
-----------------------------------------------------------------------
function utilities.remark()
	editor.invokeCommand("Comment: Add")
	local line = string.format('${os.date("%%d %%B %%Y, %%H:%%M", %d)}', os.time())
	local me = identity.own()
	if me and me.name and me.name ~= "" then
		line = line .. " -- @" .. me.name
	end

	local text = editor.getText()
	local cursor = editor.getCursor()
	-- The opening line of the comment the built-in just made: the last
	-- "<!--" before the cursor.
	local open, search = nil, 1
	while true do
		local found = string.find(text, "<!--", search, true)
		if not found or found > cursor + 1 then break end
		open, search = found, found + 1
	end
	if not open then
		editor.insertAtCursor(line)
		return
	end
	local lineStart = open
	while lineStart > 1 and string.sub(text, lineStart - 1, lineStart - 1) ~= "\n" do
		lineStart = lineStart - 1
	end
	local indent = string.match(string.sub(text, lineStart, open - 1), "^%s*")
	local openEnd = open + 3              -- 0-based offset just after "<!--"
	local inserted = "\n" .. indent .. line
	editor.replaceRange(openEnd, openEnd, inserted)
	-- The cursor stays where the built-in left it: the empty line, or the
	-- blank line after a quoted selection.
	editor.moveCursor(cursor + #inserted)
end

-----------------------------------------------------------------------
-- Command: Comment: Add Remark
--
-- Palette entry for utilities.remark(). It takes no key binding,
-- so the built-in "Comment: Add" keeps its own.
-----------------------------------------------------------------------
command.define {
	name = "Comment: Add Remark",
	run = function()
		utilities.remark()
	end
}

-----------------------------------------------------------------------
-- Slash command: /remark
--
-- Beside the built-in /comment, which SilverBullet keeps listing: a slash
-- command of the same name would not replace it, so this one has a name
-- of its own.
-----------------------------------------------------------------------
slashCommand.define {
	name = "remark",
	description = "Comment with date, time and author",
	run = function()
		utilities.remark()
	end
}
