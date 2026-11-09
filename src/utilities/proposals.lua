
-----------------------------------------------------------------------
-- Package utilities (proposals)
--
-- A proposal is a page, typically written by an agent that may not
-- write the target page itself: tag `proposal`, frontmatter `target`
-- (a page link) and `outcome`, then pairs of fenced blocks
-- ~~~~expected / ~~~~replacement. ${utilities.proposals()} lists the
-- open proposals; each links to its review, the virtual page
-- proposal:<name>, which shows the change the way GitHub shows a diff
-- of a Markdown file (formatted, or as text), with Apply, Edit and
-- Reject; the person who clicks Apply writes the target page with
-- their own rights.
--
-- Outcomes: open (or none), applied, rejected, stale. Only open and
-- stale proposals are listed.
--
-- The diff is computed by jsdiff (BSD-3-Clause), embedded in
-- jsdiff.lua and imported from a data: URL, so nothing is loaded
-- from the network.
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- utilities.jsdiff()
--
-- The jsdiff module, imported once.
-----------------------------------------------------------------------
function utilities.jsdiff()
	if not utilities.jsdiffModule then
		utilities.jsdiffModule = js.import("data:text/javascript;base64," .. utilities.jsdiffSource)
	end
	return utilities.jsdiffModule
end

-----------------------------------------------------------------------
-- utilities.unlink(value)
--
-- "[[Some/Page]]" -> "Some/Page"
-----------------------------------------------------------------------
function utilities.unlink(value)
	if type(value) ~= "string" then return nil end
	return string.match(value, "^%[%[(.-)%]%]$") or value
end

-----------------------------------------------------------------------
-- utilities.readProposal(name)
--
-- Reads a proposal page.
--
-- Returns:
--   Table { name, target, task, outcome, reason, changes = { {expected,
--   replacement} } }, or nil and an error message. The outcome is the
--   one just written (utilities.recentOutcomes) when the index has not
--   caught up yet; the reason is the text between the frontmatter and
--   the first fence.
-----------------------------------------------------------------------
function utilities.readProposal(name)
	local page = (query[[from p = index.pages() where p.name == name]])[1]
	if not page then return nil, "no such page" end
	local target = utilities.unlink(page.target)
	if not target then return nil, "no target in the frontmatter" end
	local text = "\n" .. space.readPage(name)
	local blocks = {}
	for kind, body in string.gmatch(text, "\n~~~~(%a+)\n(.-)\n~~~~") do
		table.insert(blocks, { kind = kind, body = body })
	end
	local changes = {}
	local i = 1
	while i <= #blocks do
		if blocks[i].kind == "expected" and blocks[i + 1] and blocks[i + 1].kind == "replacement" then
			table.insert(changes, { expected = blocks[i].body, replacement = blocks[i + 1].body })
			i = i + 2
		else
			return nil, "block " .. i .. " is not an expected/replacement pair"
		end
	end
	if #changes == 0 then return nil, "no changes" end
	local reason = string.match(utilities.stripFrontmatter(string.sub(text, 2)), "^(.-)\n~~~~") or ""
	reason = string.gsub(reason, "^%s+", "")
	reason = string.gsub(reason, "%s+$", "")
	return {
		name = name,
		target = target,
		task = page.task,
		outcome = utilities.recentOutcomes[name] or page.outcome or "open",
		reason = reason,
		changes = changes
	}
end

-----------------------------------------------------------------------
-- utilities.applyChanges(text, changes)
--
-- The text after the changes. Every expected text must occur exactly
-- once (the stale check).
--
-- Returns:
--   The new text, or nil and an error message.
-----------------------------------------------------------------------
function utilities.applyChanges(text, changes)
	for n, change in ipairs(changes) do
		local first = string.find(text, change.expected, 1, true)
		if not first then return nil, "change " .. n .. ": the expected text is not in the page" end
		if string.find(text, change.expected, first + 1, true) then
			return nil, "change " .. n .. ": the expected text occurs more than once"
		end
		local before = string.sub(text, 1, first - 1)
		local after = string.sub(text, first + #change.expected)
		text = before .. change.replacement .. after
	end
	return text
end

-----------------------------------------------------------------------
-- utilities.lines(value)
--
-- The lines of a diff part, without the final line break.
-----------------------------------------------------------------------
function utilities.lines(value)
	local out = {}
	local trimmed = string.gsub(value, "\n$", "")
	for line in string.gmatch(trimmed .. "\n", "(.-)\n") do table.insert(out, line) end
	return out
end

-----------------------------------------------------------------------
-- utilities.el(tag, attributes, text)
--
-- A DOM element with `text` as a plain text node. String children of
-- the dom API are rendered as markdown, which would turn "# x" into a
-- heading and [[x]] into a link, so text from a page never goes in as
-- a string child.
-----------------------------------------------------------------------
function utilities.el(tag, attributes, text)
	local element = dom[tag](attributes or {})
	if text ~= nil then
		element.appendChild(js.window.document.createTextNode(tostring(text)))
	end
	return element
end

-- Colours that read on light and dark themes alike.
utilities.diffColours = {
	removedLine = "rgba(255,129,130,0.15)",
	removedWord = "rgba(255,129,130,0.45)",
	addedLine = "rgba(46,160,67,0.15)",
	addedWord = "rgba(46,160,67,0.45)",
	removedBar = "rgb(207,34,46)",
	addedBar = "rgb(26,127,55)"
}

-----------------------------------------------------------------------
-- utilities.codeLine(segments, colour)
--
-- One line of the text diff as a DOM node: segments are { text,
-- highlighted } pairs, highlighted ones get the word colour.
-----------------------------------------------------------------------
function utilities.codeLine(segments, colour)
	local cell = dom.td { style = "white-space:pre-wrap;word-break:break-word;padding:0 0.5em;font-family:var(--editor-font, monospace);" }
	for _, s in ipairs(segments) do
		if s[2] then
			cell.appendChild(utilities.el("span", { style = "background:" .. colour .. ";border-radius:2px;" }, s[1]))
		else
			cell.appendChild(utilities.el("span", {}, s[1]))
		end
	end
	return cell
end

-----------------------------------------------------------------------
-- utilities.textDiff(old, new)
--
-- The text view: changed lines with three lines of context, removed
-- in red, added in green, changed words highlighted when a block of
-- removed lines is followed by as many added ones.
-----------------------------------------------------------------------
function utilities.textDiff(old, new)
	local m = utilities.jsdiff()
	local c = utilities.diffColours
	local parts = m.diffLines(old, new)
	-- flatten into rows { kind, oldNo, newNo, segments }
	local rows = {}
	local oldNo, newNo = 1, 1
	local i = 1
	while i <= parts.length do
		local p = parts[i]
		local nextPart = (i < parts.length) and parts[i + 1] or nil
		if p.removed and nextPart and nextPart.added and #utilities.lines(p.value) == #utilities.lines(nextPart.value) then
			local removedLines, addedLines = utilities.lines(p.value), utilities.lines(nextPart.value)
			local pendingAdded = {}
			for k = 1, #removedLines do
				local words = m.diffWordsWithSpace(removedLines[k], addedLines[k])
				local minus, plus = {}, {}
				for w = 1, words.length do
					local word = words[w]
					if word.removed then table.insert(minus, { word.value, true })
					elseif word.added then table.insert(plus, { word.value, true })
					else
						table.insert(minus, { word.value, false })
						table.insert(plus, { word.value, false })
					end
				end
				table.insert(rows, { kind = "-", oldNo = oldNo, segments = minus })
				oldNo = oldNo + 1
				table.insert(pendingAdded, plus)
			end
			for _, plus in ipairs(pendingAdded) do
				table.insert(rows, { kind = "+", newNo = newNo, segments = plus })
				newNo = newNo + 1
			end
			i = i + 2
		else
			for _, line in ipairs(utilities.lines(p.value)) do
				if p.removed then
					table.insert(rows, { kind = "-", oldNo = oldNo, segments = { { line, false } } })
					oldNo = oldNo + 1
				elseif p.added then
					table.insert(rows, { kind = "+", newNo = newNo, segments = { { line, false } } })
					newNo = newNo + 1
				else
					table.insert(rows, { kind = " ", oldNo = oldNo, newNo = newNo, segments = { { line, false } } })
					oldNo, newNo = oldNo + 1, newNo + 1
				end
			end
			i = i + 1
		end
	end
	-- keep three lines of context around every change
	local keep = {}
	for n, row in ipairs(rows) do
		if row.kind ~= " " then
			for k = math.max(1, n - 3), math.min(#rows, n + 3) do keep[k] = true end
		end
	end
	local tbl = dom.table { style = "border-collapse:collapse;width:100%;font-size:0.85em;" }
	local skipped = 0
	local function flushSkipped()
		if skipped > 0 then
			local tr = dom.tr {}
			tr.appendChild(utilities.el("td", { colspan = "4", style = "opacity:0.6;padding:0.2em 0.5em;font-style:italic;" },
				skipped .. " unchanged line" .. (skipped == 1 and "" or "s")))
			tbl.appendChild(tr)
			skipped = 0
		end
	end
	for n, row in ipairs(rows) do
		if keep[n] then
			flushSkipped()
			local bg, word = "transparent", nil
			if row.kind == "-" then bg, word = c.removedLine, c.removedWord end
			if row.kind == "+" then bg, word = c.addedLine, c.addedWord end
			local num = "opacity:0.5;text-align:right;padding:0 0.4em;user-select:none;font-family:monospace;"
			local tr = dom.tr { style = "background:" .. bg .. ";" }
			tr.appendChild(utilities.el("td", { style = num }, row.oldNo or ""))
			tr.appendChild(utilities.el("td", { style = num }, row.newNo or ""))
			tr.appendChild(utilities.el("td", { style = "user-select:none;font-family:monospace;padding:0 0.2em;" }, row.kind))
			tr.appendChild(utilities.codeLine(row.segments, word or bg))
			tbl.appendChild(tr)
		else
			skipped = skipped + 1
		end
	end
	flushSkipped()
	return tbl
end

-----------------------------------------------------------------------
-- utilities.stripFrontmatter(text)
-----------------------------------------------------------------------
function utilities.stripFrontmatter(text)
	local body = string.match(text, "^%-%-%-\n.-\n%-%-%-\n(.*)$")
	return body or text
end

-----------------------------------------------------------------------
-- utilities.formattedDiff(old, new)
--
-- The formatted view: the page as it will look, rendered by
-- SilverBullet's own markdown renderer (which shows ${...} as text
-- and drops scripts and event handlers); removed text struck through
-- on red, added text on green. Blocks (separated by blank lines, a
-- heading on its own) that are unchanged render as they are; a
-- changed block is compared line by line, a changed table row by row,
-- so only what changed is coloured.
-----------------------------------------------------------------------
function utilities.formattedDiff(old, new)
	local m = utilities.jsdiff()
	local c = utilities.diffColours
	local container = dom.div { style = "display:flex;flex-direction:column;gap:0.3em;" }

	local function render(text, kind)
		local style = "padding:0.1em 0.6em;"
		if kind == "-" then
			style = style .. "background:" .. c.removedLine .. ";border-left:3px solid " .. c.removedBar .. ";text-decoration:line-through;opacity:0.85;"
		elseif kind == "+" then
			style = style .. "background:" .. c.addedLine .. ";border-left:3px solid " .. c.addedBar .. ";"
		else
			style = style .. "border-left:3px solid transparent;"
		end
		local block = dom.div { style = style }
		block.innerHTML = markdown.markdownToHtml(text)
		container.appendChild(block)
	end

	-- the blocks of a page: separated by blank lines, and a heading is a
	-- block of its own, because a page often puts its text directly under
	-- the heading (as a decision record does)
	local function blocks(text)
		local out = {}
		for block in string.gmatch(utilities.stripFrontmatter(text) .. "\n\n", "(.-)\n[ \t]*\n") do
			local current = {}
			for _, line in ipairs(utilities.lines(block)) do
				if string.find(line, "^#+ ") then
					if #current > 0 then table.insert(out, table.concat(current, "\n")) end
					table.insert(out, line)
					current = {}
				else
					table.insert(current, line)
				end
			end
			if #current > 0 then table.insert(out, table.concat(current, "\n")) end
		end
		local kept = {}
		for _, block in ipairs(out) do
			if string.find(block, "%S") then table.insert(kept, block) end
		end
		return kept
	end

	-- a changed block, line by line: only the changed lines are coloured,
	-- so an edited list item does not repeat the list and an edited line
	-- of a paragraph does not strike the paragraph
	local function lineDiff(before, after)
		local items = m.diffArrays(js.tojs(utilities.lines(before)), js.tojs(utilities.lines(after)))
		for i = 1, items.length do
			local part = items[i]
			local kind = part.removed and "-" or (part.added and "+" or " ")
			local lines = {}
			for k = 1, part.value.length do table.insert(lines, part.value[k]) end
			render(table.concat(lines, "\n"), kind)
		end
	end

	local function isTable(block)
		local lines = utilities.lines(block)
		if #lines < 2 then return false end
		for _, line in ipairs(lines) do
			if not string.find(line, "^%s*|") then return false end
		end
		return true
	end

	-- a changed table: one table holding the removed and the added rows,
	-- each row coloured, so the table keeps its shape
	local function tableDiff(before, after)
		local oldLines, newLines = utilities.lines(before), utilities.lines(after)
		local oldRows, newRows = {}, {}
		for k = 3, #oldLines do table.insert(oldRows, oldLines[k]) end
		for k = 3, #newLines do table.insert(newRows, newLines[k]) end
		local rows = m.diffArrays(js.tojs(oldRows), js.tojs(newRows))
		local lines, kinds = { newLines[1], newLines[2] }, {}
		for i = 1, rows.length do
			local part = rows[i]
			for k = 1, part.value.length do
				table.insert(lines, part.value[k])
				table.insert(kinds, part.removed and "-" or (part.added and "+" or " "))
			end
		end
		local block = dom.div { style = "padding:0.1em 0.6em;border-left:3px solid " .. c.addedBar .. ";" }
		block.innerHTML = markdown.markdownToHtml(table.concat(lines, "\n"))
		local trs = block.querySelectorAll("tr")
		for k, kind in ipairs(kinds) do
			local tr = trs[k + 1]
			if tr and kind == "-" then
				tr.style.background = c.removedWord
				tr.style.textDecoration = "line-through"
			elseif tr and kind == "+" then
				tr.style.background = c.addedWord
			end
		end
		container.appendChild(block)
	end

	local parts = m.diffArrays(js.tojs(blocks(old)), js.tojs(blocks(new)))
	local i = 1
	while i <= parts.length do
		local p = parts[i]
		local nextPart = (i < parts.length) and parts[i + 1] or nil
		if p.removed and nextPart and nextPart.added and p.value.length == nextPart.value.length then
			for k = 1, p.value.length do
				local before, after = p.value[k], nextPart.value[k]
				if isTable(before) and isTable(after) then
					tableDiff(before, after)
				else
					lineDiff(before, after)
				end
			end
			i = i + 2
		elseif p.removed and nextPart and nextPart.added then
			-- a different number of blocks (a paragraph split or joined, a
			-- block inserted among changed ones): line by line over the run
			local before, after = {}, {}
			for k = 1, p.value.length do table.insert(before, p.value[k]) end
			for k = 1, nextPart.value.length do table.insert(after, nextPart.value[k]) end
			lineDiff(table.concat(before, "\n\n"), table.concat(after, "\n\n"))
			i = i + 2
		else
			local kind = p.removed and "-" or (p.added and "+" or " ")
			for k = 1, p.value.length do render(p.value[k], kind) end
			i = i + 1
		end
	end
	return container
end


-----------------------------------------------------------------------
-- utilities.setOutcome(name, outcome)
--
-- Records the outcome in the frontmatter of a proposal page: replaces
-- its `outcome:` line, or adds one before the closing "---".
-----------------------------------------------------------------------
function utilities.setOutcome(name, outcome)
	local text = space.readPage(name)
	local frontmatter, rest = string.match(text, "^(%-%-%-\n.-\n)(%-%-%-\n.*)$")
	if not frontmatter then
		text = "---\noutcome: " .. outcome .. "\n---\n" .. text
	elseif string.find(frontmatter, "\noutcome:") or string.find(frontmatter, "^%-%-%-\noutcome:") then
		local replaced = string.gsub(frontmatter, "\noutcome:[^\n]*", "\noutcome: " .. outcome, 1)
		text = replaced .. rest
	else
		text = frontmatter .. "outcome: " .. outcome .. "\n" .. rest
	end
	space.writePage(name, text)
	utilities.recentOutcomes[name] = outcome
end

-----------------------------------------------------------------------
-- utilities.recentOutcomes
--
-- Outcomes just written, by proposal name. The index learns about the
-- write a moment later; until it has, the list uses these, so a
-- proposal disappears as soon as it is applied or rejected.
-----------------------------------------------------------------------
utilities.recentOutcomes = utilities.recentOutcomes or {}

-----------------------------------------------------------------------
-- utilities.applyProposal(name)
--
-- Applies a proposal: reads it and its target again, runs the stale
-- check, writes the target page and records `applied`. A stale
-- proposal is recorded as `stale` and the target is not touched.
--
-- Returns:
--   true, or false and the reason.
-----------------------------------------------------------------------
function utilities.applyProposal(name)
	local proposal, err = utilities.readProposal(name)
	if not proposal then return false, err end
	local ok, old = pcall(space.readPage, proposal.target)
	if not ok then return false, "the target page cannot be read" end
	local new, stale = utilities.applyChanges(old, proposal.changes)
	if not new then
		utilities.setOutcome(name, "stale")
		return false, "stale: " .. stale
	end
	space.writePage(proposal.target, new)
	utilities.setOutcome(name, "applied")
	return true
end

-----------------------------------------------------------------------
-- utilities.openProposals(target)
--
-- The names of the proposals that are open or stale, optionally only
-- those for one target page, by name.
-----------------------------------------------------------------------
function utilities.openProposals(target)
	local names = {}
	for _, p in ipairs(query[[from p = index.tag "proposal" where p.tag == "page" order by p.name]]) do
		local outcome = p.outcome or "open"
		local recent = utilities.recentOutcomes[p.name]
		if recent == outcome then
			utilities.recentOutcomes[p.name] = nil
		elseif recent then
			outcome = recent
		end
		if not utilities.excluded(p.name)
			and (outcome == "open" or outcome == "stale")
			and (target == nil or utilities.unlink(p.target) == target) then
			table.insert(names, p.name)
		end
	end
	return names
end

-----------------------------------------------------------------------
-- utilities.refresh()
--
-- Re-renders the widgets of the page shown, after an action changed
-- what they display.
-----------------------------------------------------------------------
function utilities.refresh()
	if codeWidget and codeWidget.refreshAll then codeWidget.refreshAll() end
end

-----------------------------------------------------------------------
-- utilities.reviewPage(name)
--
-- The name of the virtual page that reviews a proposal.
-----------------------------------------------------------------------
function utilities.reviewPage(name)
	return "proposal:" .. name
end

-----------------------------------------------------------------------
-- utilities.reviewLink(name)
--
-- A markdown link to the review of a proposal, labelled with the
-- proposal's name, when the name is safe in a link; a code span
-- otherwise.
-----------------------------------------------------------------------
function utilities.reviewLink(name)
	if utilities.safeName(name) then return "[[" .. utilities.reviewPage(name) .. "|" .. name .. "]]" end
	return utilities.code(name)
end

-----------------------------------------------------------------------
-- utilities.pageLink(name, label)
--
-- A link to a page (or virtual page) as a DOM node that navigates on
-- click; the label (default: the name) is a text node.
-----------------------------------------------------------------------
function utilities.pageLink(name, label, style)
	return utilities.el("a", {
		style = "cursor:pointer;" .. (style or ""),
		onclick = function() editor.navigate({ kind = "page", page = name }) end
	}, label or name)
end

-----------------------------------------------------------------------
-- utilities.proposalView(name)
--
-- The review of one proposal as a DOM node: the proposal (a link to
-- its page), target, task and outcome, the reason, a switch between
-- the formatted and the text diff (formatted first), and Apply / Edit
-- / Reject. A stale proposal shows why, and Close records it as
-- stale. A proposal that is applied or rejected shows its outcome and
-- no buttons.
-----------------------------------------------------------------------
function utilities.proposalView(name)
	local c = utilities.diffColours
	local container = dom.div { class = "utilities-proposal", style = "border:1px solid rgba(128,128,128,0.4);border-radius:6px;overflow:hidden;" }
	local header = dom.div { style = "display:flex;gap:0.5em;align-items:center;padding:0.4em 5em 0.4em 0.6em;background:rgba(128,128,128,0.12);border-bottom:1px solid rgba(128,128,128,0.4);flex-wrap:wrap;" }
	container.appendChild(header)
	local proposal, err = utilities.readProposal(name)
	local old, new, stale
	if proposal then
		local ok, text = pcall(space.readPage, proposal.target)
		if ok then
			old = text
			new, stale = utilities.applyChanges(old, proposal.changes)
		else
			stale = "the target page " .. proposal.target .. " cannot be read"
		end
	else
		stale = err
	end
	header.appendChild(utilities.pageLink(name, name, "font-weight:bold;"))
	if proposal then
		local info = utilities.el("span", { style = "opacity:0.7;" }, "→ ")
		info.appendChild(utilities.pageLink(proposal.target))
		local facts = " · " .. #proposal.changes .. " change" .. (#proposal.changes == 1 and "" or "s")
		if proposal.task then facts = facts .. " · task " .. tostring(proposal.task) end
		facts = facts .. " · " .. proposal.outcome
		info.appendChild(js.window.document.createTextNode(facts))
		header.appendChild(info)
	end
	header.appendChild(dom.span { style = "flex:1;" })

	local function act(action)
		local ok, why = action()
		if not ok then editor.flashNotification(name .. ": " .. tostring(why), "error") end
		utilities.refresh()
	end

	local body = dom.div { style = "padding:0.4em 0;" }
	if proposal and proposal.reason ~= "" then
		body.appendChild(utilities.el("div", { style = "padding:0.2em 0.6em 0.6em 0.6em;white-space:pre-wrap;opacity:0.85;" }, proposal.reason))
	end

	-- the two views and the buttons that switch between them
	local function addViews()
		local formattedView = utilities.formattedDiff(old, new)
		local textView = utilities.textDiff(old, new)
		textView.style.display = "none"
		local formattedButton, textButton
		local function show(which)
			formattedView.style.display = (which == "formatted") and "flex" or "none"
			textView.style.display = (which == "text") and "" or "none"
			formattedButton.style.fontWeight = (which == "formatted") and "bold" or "normal"
			textButton.style.fontWeight = (which == "text") and "bold" or "normal"
		end
		formattedButton = utilities.el("button", { onclick = function() show("formatted") end }, "Formatted")
		textButton = utilities.el("button", { onclick = function() show("text") end }, "Text")
		formattedButton.style.fontWeight = "bold"
		header.appendChild(formattedButton)
		header.appendChild(textButton)
		body.appendChild(formattedView)
		body.appendChild(textView)
	end

	local closed = proposal and proposal.outcome ~= "open" and proposal.outcome ~= "stale"
	if closed then
		body.appendChild(utilities.el("div", { style = "padding:0.4em 0.6em;font-style:italic;" }, "This proposal is " .. proposal.outcome .. "; nothing to do."))
		if new then addViews() end
		container.appendChild(body)
		return container
	end

	if not new then
		body.appendChild(utilities.el("div", { style = "padding:0.6em;background:" .. c.removedLine .. ";" }, "Cannot be applied: " .. tostring(stale)))
		header.appendChild(utilities.el("button", { onclick = function() editor.navigate({ kind = "page", page = name }) end }, "Edit"))
		if proposal and proposal.outcome ~= "stale" then
			header.appendChild(utilities.el("button", { onclick = function()
				act(function() utilities.setOutcome(name, "stale"); return true end)
			end }, "Close as stale"))
		end
		container.appendChild(body)
		return container
	end

	addViews()
	header.appendChild(utilities.el("button", { onclick = function()
		act(function() return utilities.applyProposal(name) end)
	end }, "Apply"))
	header.appendChild(utilities.el("button", { onclick = function() editor.navigate({ kind = "page", page = name }) end }, "Edit"))
	header.appendChild(utilities.el("button", { onclick = function()
		act(function() utilities.setOutcome(name, "rejected"); return true end)
	end }, "Reject"))
	container.appendChild(body)
	return container
end

-----------------------------------------------------------------------
-- utilities.review(name)
--
-- The review of one proposal as a block widget. ${utilities.review()}
-- on the virtual page proposal:<name> takes the name from the page
-- shown; ${utilities.review("Some/Proposal")} reviews that proposal on
-- any page.
--
-- Returns:
--   A block widget.
-----------------------------------------------------------------------
function utilities.review(name)
	if name == nil then
		name = string.match(editor.getCurrentPage() or "", "^proposal:(.+)$")
	end
	if not name then return widget.markdownBlock("*No proposal named.*") end
	return widget.new { html = utilities.proposalView(name), display = "block" }
end

-----------------------------------------------------------------------
-- utilities.reviewPageText(name)
--
-- The markdown of the virtual page proposal:<name>: a heading that
-- links to the proposal page, and the review widget. The name goes in
-- through utilities.link, so a name that could break a link is shown
-- as a code span; the widget takes the name from the page shown, not
-- from the markdown.
-----------------------------------------------------------------------
function utilities.reviewPageText(name)
	return "# Review of " .. utilities.link(name) .. "\n\n${utilities.review()}\n"
end

virtualPage.define {
	pattern = "proposal:(.+)",
	run = function(name)
		return utilities.reviewPageText(name)
	end
}

-----------------------------------------------------------------------
-- utilities.proposals(target)
--
-- The list of open proposals: ${utilities.proposals()} lists every
-- one, ${utilities.proposals("Some/Page")} only those for that page.
-- One row per proposal, linking to its review (proposal:<name>) and
-- to its target page, with the number of changes, the task and the
-- outcome. "Apply all" applies every listed proposal that is not
-- stale, after a confirmation that names the target pages.
--
-- Returns:
--   A block widget.
-----------------------------------------------------------------------
function utilities.proposals(target)
	local names = utilities.openProposals(target)
	if #names == 0 then
		return widget.markdownBlock("*No open proposals.*")
	end
	local container = dom.div { class = "utilities-proposals", style = "display:flex;flex-direction:column;gap:0.5em;" }
	local bar = dom.div { style = "display:flex;gap:0.5em;align-items:center;padding-right:5em;" }
	bar.appendChild(utilities.el("span", { style = "opacity:0.7;" }, #names .. " open proposal" .. (#names == 1 and "" or "s")))
	bar.appendChild(utilities.el("button", { onclick = function()
		local targets, seen = {}, {}
		for _, name in ipairs(names) do
			local proposal = utilities.readProposal(name)
			if proposal and not seen[proposal.target] then
				seen[proposal.target] = true
				table.insert(targets, proposal.target)
			end
		end
		if not editor.confirm("Apply " .. #names .. " proposal(s) to: " .. table.concat(targets, ", ") .. "?") then return end
		local applied, failed = 0, {}
		for _, name in ipairs(names) do
			local ok, why = utilities.applyProposal(name)
			if ok then applied = applied + 1 else table.insert(failed, name .. " (" .. tostring(why) .. ")") end
		end
		local message = applied .. " applied"
		if #failed > 0 then message = message .. "; not applied: " .. table.concat(failed, "; ") end
		editor.flashNotification(message, #failed > 0 and "error" or "info")
		utilities.refresh()
	end }, "Apply all"))
	container.appendChild(bar)

	local th = "text-align:left;padding:0.2em 1em 0.2em 0;border-bottom:1px solid rgba(128,128,128,0.4);font-weight:bold;"
	local td = "padding:0.25em 1em 0.25em 0;vertical-align:top;"
	local tbl = dom.table { style = "border-collapse:collapse;" }
	local head = dom.tr {}
	for _, label in ipairs({ "Proposal", "Target", "Changes", "Task", "State" }) do
		head.appendChild(utilities.el("th", { style = th }, label))
	end
	tbl.appendChild(head)
	for _, name in ipairs(names) do
		local proposal, err = utilities.readProposal(name)
		local tr = dom.tr {}
		local first = dom.td { style = td }
		first.appendChild(utilities.pageLink(utilities.reviewPage(name), name))
		tr.appendChild(first)
		if proposal then
			local targetCell = dom.td { style = td }
			targetCell.appendChild(utilities.pageLink(proposal.target))
			tr.appendChild(targetCell)
			tr.appendChild(utilities.el("td", { style = td .. "text-align:right;" }, #proposal.changes))
			tr.appendChild(utilities.el("td", { style = td }, proposal.task or ""))
			tr.appendChild(utilities.el("td", { style = td }, proposal.outcome))
		else
			tr.appendChild(utilities.el("td", { style = td, colspan = "4" }, "cannot be read: " .. tostring(err)))
		end
		tbl.appendChild(tr)
	end
	container.appendChild(tbl)
	return widget.new { html = container, display = "block" }
end
