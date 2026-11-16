-----------------------------------------------------------------------
-- utilities.signedComment()
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
-- built-in put there (a quoted selection follows it), and the cursor
-- sits on a new line below it, ready to type.
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
function utilities.signedComment()
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
	local openEnd = open + 4              -- 1-based, just after "<!--"
	local nextEnd = string.find(text, "\n", openEnd + 1, true) or #text + 1
	local blank = string.match(string.sub(text, openEnd + 1, nextEnd - 1), "^%s*$") ~= nil
	if blank then
		-- No selection: the built-in left an empty line for the cursor.
		-- The date line goes above it; the cursor stays on it.
		editor.replaceRange(openEnd - 1, openEnd - 1, "\n" .. indent .. line)
		editor.moveCursor(nextEnd - 1 + #indent + #line + 1)
	else
		-- A quoted selection sits there: the date line and a new line for
		-- the cursor go above it.
		editor.replaceRange(openEnd - 1, openEnd - 1, "\n" .. indent .. line .. "\n" .. indent)
		editor.moveCursor(openEnd - 1 + 1 + #indent + #line + 1 + #indent)
	end
end

-----------------------------------------------------------------------
-- Command: Utilities: Signed Comment
--
-- Palette entry for utilities.signedComment(). It takes no key binding,
-- so the built-in "Comment: Add" keeps its own.
-----------------------------------------------------------------------
command.define {
	name = "Utilities: Signed Comment",
	run = function()
		utilities.signedComment()
	end
}

-----------------------------------------------------------------------
-- Slash command: /signedComment
--
-- Found when "comment" is typed (the menu matches the name; `aliases`
-- is used by later SilverBullet releases), beside the built-in /comment,
-- which SilverBullet keeps listing: a slash command of the same name
-- would not replace it.
-----------------------------------------------------------------------
slashCommand.define {
	name = "signedComment",
	aliases = { "comment" },
	description = "Comment with date, time and author",
	run = function()
		utilities.signedComment()
	end
}
