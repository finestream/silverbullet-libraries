-----------------------------------------------------------------------
-- utilities.signedComment()
--
-- Adds a comment like SilverBullet's own "Comment: Add" does (after the
-- current block, indented inside a list item, the selection quoted) and
-- starts it with the moment and the author:
--
--   <!--
--   ${os.date("%d %B %Y, %H:%M", 1795000000)} -- @name
--   -->
--
-- The moment is stored as seconds since the epoch, so the page keeps an
-- absolute time; os.date shows it in the time zone of the browser that
-- renders the page, so every reader sees it in their own. The name is
-- identity.own(), the logged-in user, as a signature (" -- @name"), which
-- does not address the author the way a bare @name would. Where the
-- space does not know the user, the line holds the moment only.
--
-- The built-in command stays as it is; this one runs it and then writes
-- the line where it left the cursor.
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
	editor.insertAtCursor(line)
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
-- Found when "comment" is typed (alias), beside the built-in /comment,
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
