
-----------------------------------------------------------------------
-- Package views
--
-- Views.
--
-- What pages call. Every object page ends with the same call,
-- ${views.page(_CTX.currentPage.name)}: it looks at the page's tags
-- and shows the view for its kind. A view shows what is derived or
-- points to the page; what the page itself states stays in its
-- frontmatter. Every section is always shown; an empty one says
-- *none*. Lists are sorted by `type`, in the order of the type list,
-- then by name.
-----------------------------------------------------------------------
views = {}

-----------------------------------------------------------------------
-- views.linkedTo(tagName, field, target)
--
-- Pages tagged `tagName` whose `field` (one link or a list of links)
-- points to `target`
-----------------------------------------------------------------------
function views.linkedTo(tagName, field, target)
	local wanted, found = itam.link(target), {}
	for _, page in ipairs(itam.pages(tagName)) do
		for _, value in ipairs(itam.list(page[field])) do
			if value == wanted then
				table.insert(found, page)
				break
			end
		end
	end
	return found
end

-----------------------------------------------------------------------
-- sortByType(pages, kind)
--
-- By the position of the (first) type in the type list of `kind`, then
-- by name
-----------------------------------------------------------------------
local function sortByType(pages, kind)
	local rank = {}
	for i, t in ipairs(itam.typesOf(kind)) do rank[t] = i end
	table.sort(pages, function(a, b)
		local rankA = rank[itam.list(a.type)[1]] or 999
		local rankB = rank[itam.list(b.type)[1]] or 999
		if rankA ~= rankB then return rankA < rankB end
		return a.name < b.name
	end)
	return pages
end

-----------------------------------------------------------------------
-- sortByName(pages)
--
-- Sorts the pages by name, in place, and returns them.
-----------------------------------------------------------------------
local function sortByName(pages)
	table.sort(pages, function(a, b) return a.name < b.name end)
	return pages
end

-----------------------------------------------------------------------
-- Building blocks: Markdown tables, diagrams, and one block for both
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- cell(value)
--
-- One table cell as text: nil is empty, a list is joined with commas,
-- a pipe is escaped so it stays in its cell.
-----------------------------------------------------------------------
local function cell(value)
	if value == nil then return "" end
	if type(value) == "table" then value = table.concat(value, ", ") end
	local escaped = string.gsub(tostring(value), "|", "\\|")
	return escaped
end

-----------------------------------------------------------------------
-- section(title, columns, rows)
--
-- A titled table; "none" when there are no rows
-----------------------------------------------------------------------
local function section(title, columns, rows)
	local out = { "**" .. title .. "**", "" }
	if #rows == 0 then
		table.insert(out, "none")
	else
		local rule = {}
		for i = 1, #columns do rule[i] = "---" end
		table.insert(out, "| " .. table.concat(columns, " | ") .. " |")
		table.insert(out, "| " .. table.concat(rule, " | ") .. " |")
		for _, row in ipairs(rows) do
			local cells = {}
			for i = 1, #columns do cells[i] = cell(row[i]) end
			table.insert(out, "| " .. table.concat(cells, " | ") .. " |")
		end
	end
	table.insert(out, "")
	return table.concat(out, "\n")
end

-----------------------------------------------------------------------
-- pageRows(pages, fields)
--
-- One row per page: a link to the page, then the given fields
-----------------------------------------------------------------------
local function pageRows(pages, fields)
	local rows = {}
	for _, page in ipairs(pages) do
		local row = { itam.link(page.name) }
		for i, field in ipairs(fields) do row[i + 1] = page[field] end
		table.insert(rows, row)
	end
	return rows
end

-----------------------------------------------------------------------
-- addDiagram(parts, title, diagram)
--
-- A titled diagram, added to `parts`; "none" when there is nothing to
-- draw
-----------------------------------------------------------------------
local function addDiagram(parts, title, diagram)
	if diagram then
		table.insert(parts, "**" .. title .. "**\n")
		table.insert(parts, diagram)
	else
		table.insert(parts, "**" .. title .. "**\n\nnone\n")
	end
end

-----------------------------------------------------------------------
-- compose(parts)
--
-- Sections are Markdown strings, diagrams are widgets. Without a
-- diagram the result is one Markdown block; with one, everything
-- becomes one HTML block.
-----------------------------------------------------------------------
local function compose(parts)
	local hasDiagram = false
	for _, part in ipairs(parts) do
		if type(part) ~= "string" then hasDiagram = true end
	end
	if not hasDiagram then
		return widget.markdownBlock(table.concat(parts, "\n"))
	end
	local html, events = {}, nil
	for _, part in ipairs(parts) do
		if type(part) == "string" then
			table.insert(html, markdown.markdownToHtml(part))
		else
			table.insert(html, part.html)
			events = events or part.events
		end
	end
	return widget.new { html = table.concat(html), display = "block", events = events }
end

-----------------------------------------------------------------------
-- views.section
--
-- Shared with the decision views below
-----------------------------------------------------------------------
views.section = section
views.pageRows = pageRows
views.sortByName = sortByName

-----------------------------------------------------------------------
-- kinds
--
-- Every kind: its title, and the fields its index page shows after
-- name and type
-----------------------------------------------------------------------
local kinds = {
	host    = { title = "Hosts",     fields = { "role", "location", "status" } },
	service = { title = "Services",  fields = { "partOf", "purpose", "status" } },
	storage = { title = "Storage",   fields = { "partOf", "policies", "status" } },
	network = { title = "Networks",  fields = { "partOf", "cidr", "location" } },
	policy  = { title = "Policies",  fields = { "copies", "offsite", "frequency" } },
	job     = { title = "Jobs",      fields = { "partOf", "tool", "schedule" } },
	dr      = { title = "Decisions", fields = { "id", "status" } },
}

-----------------------------------------------------------------------
-- Diagrams
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- views.network(name)
--
-- A network and everything on it (hosts and services), arrows pointing
-- to the network
-----------------------------------------------------------------------
function views.network(name)
	local pages = views.linkedTo("component", "network", name)
	local self = itam.page(name)
	if self then table.insert(pages, 1, self) end
	return mermaid.diagram(mermaid.relationGraph {
		pages = pages, relations = { "network" }, direction = "LR",
	})
end

-----------------------------------------------------------------------
-- views.stack(name)
--
-- The storage layers below `name` (along `on`) and above it; nil when
-- it stands alone
-----------------------------------------------------------------------
function views.stack(name)
	local byName = itam.byName("storage")
	local below, above = {}, {}
	for upper, page in pairs(byName) do
		below[upper] = {}
		for _, value in ipairs(itam.list(page.on)) do
			local lower = itam.unlink(value)
			table.insert(below[upper], lower)
			above[lower] = above[lower] or {}
			table.insert(above[lower], upper)
		end
	end
	for _, uppers in pairs(above) do table.sort(uppers) end

	local chart, edges = itam.flowchart(), {}
	local function box(n)
		local page = byName[n]
		chart.box(n, itam.short(n) .. ((page and page.type) and (" · " .. page.type) or ""), nil, "rounded")
	end
	local function edge(upper, lower)
		local key = upper .. " > " .. lower
		if not edges[key] then
			edges[key] = true
			chart.edge(upper, lower)
		end
	end
	-- Breadth first from `name` along `neighbours`; `down` says which way the arrows point
	local function walk(neighbours, down)
		local queue, seen = { name }, {}
		seen[name] = true
		while #queue > 0 do
			local current = table.remove(queue, 1)
			for _, other in ipairs(neighbours[current] or {}) do
				if down then edge(current, other) else edge(other, current) end
				box(other)
				if not seen[other] then
					seen[other] = true
					table.insert(queue, other)
				end
			end
		end
	end

	box(name)
	walk(below, true)
	walk(above, false)
	if chart.size == 1 then return nil end
	return chart.render("TB")
end

-----------------------------------------------------------------------
-- views.architecture()
--
-- Hosts grouped by site (free reservations left out), each with an
-- arrow to the networks it is on: LANs, VPNs, internet. A LAN is drawn
-- inside its site; the hosts of type external in the configured
-- providers group.
-----------------------------------------------------------------------
function views.architecture()
	local cfg = itam.config()
	local nets = {}
	for _, page in ipairs(itam.pages("network")) do
		if page.type == "lan" or page.type == "tailnet" or page.type == "internet" then
			nets[page.name] = page
		end
	end
	local hosts = {}
	for _, page in ipairs(itam.pages("host")) do
		if page.type ~= "unused" and itam.inScope(page.name) then table.insert(hosts, page) end
	end

	local chart, used = itam.flowchart(), {}
	for _, host in ipairs(sortByType(hosts, "host")) do
		chart.box(host.name, nil, host.location or cfg.providers, "rounded")
		for _, value in ipairs(itam.list(host.network)) do
			local net = itam.unlink(value)
			if nets[net] then
				used[net] = true
				chart.edge(host.name, net)
			end
		end
	end
	local netNames = {}
	for name in pairs(used) do table.insert(netNames, name) end
	table.sort(netNames)
	for _, name in ipairs(netNames) do
		local page = nets[name]
		local inSite = page.type == "lan" and page.location and chart.groups[page.location]
		chart.box(name, nil, inSite and page.location or nil)
	end

	local order = {}
	for _, site in ipairs(cfg.sites) do table.insert(order, site) end
	table.insert(order, cfg.providers)
	return chart.render("LR", order)
end

-----------------------------------------------------------------------
-- Tables beyond one page
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- views.index(tagName)
--
-- Every object of one kind under the configured roots, sorted by type
-----------------------------------------------------------------------
function views.index(tagName)
	local kind = kinds[tagName] or { title = tagName, fields = {} }
	local pages = {}
	for _, page in ipairs(itam.pages(tagName)) do
		if itam.inScope(page.name) then table.insert(pages, page) end
	end
	local fields = {}
	if itam.types[tagName] then
		sortByType(pages, tagName)
		table.insert(fields, "type")
	else
		sortByName(pages)
	end
	for _, field in ipairs(kind.fields) do table.insert(fields, field) end

	local columns = { "name" }
	for _, field in ipairs(fields) do
		table.insert(columns, (field == "partOf") and "host" or field)
	end
	return widget.markdownBlock(section(kind.title, columns, pageRows(pages, fields)))
end

-----------------------------------------------------------------------
-- copyRows(storagePages, withType)
--
-- Copies and offsite copies of each storage in `storagePages`, as
-- table rows
-----------------------------------------------------------------------
local function copyRows(storagePages, withType)
	local pages, jobs, rows = itam.byName("component"), itam.pages("job"), {}
	for _, page in ipairs(storagePages) do
		local summary = backup.summary(page.name, backup.chain(page.name, jobs), pages)
		if withType then
			table.insert(rows, { itam.link(page.name), page.type, summary.copies, summary.offsite })
		else
			table.insert(rows, { itam.link(page.name), summary.copies, summary.offsite })
		end
	end
	return rows
end

-----------------------------------------------------------------------
-- views.copies()
--
-- Every storage that has a policy, with its copies and offsite copies
-----------------------------------------------------------------------
function views.copies()
	local protected = {}
	for _, page in ipairs(itam.pages("storage")) do
		if page.policies and itam.inScope(page.name) then table.insert(protected, page) end
	end
	return widget.markdownBlock(section("Copies of each protected storage",
		{ "storage", "copies", "offsite" }, copyRows(sortByName(protected), false)))
end

-----------------------------------------------------------------------
-- One view per kind
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- hostView(name)
--
-- Host: what is partOf it, in the order: what it offers, holds, runs,
-- connects to
-----------------------------------------------------------------------
local function hostView(name)
	local members, parts = views.linkedTo("component", "partOf", name), {}
	for _, tagName in ipairs({ "service", "storage", "job", "network" }) do
		local pages = {}
		for _, page in ipairs(members) do
			if itam.hasTag(page, tagName) then table.insert(pages, page) end
		end
		table.insert(parts, section(kinds[tagName].title, { "name", "type" },
			pageRows(sortByType(pages, tagName), { "type" })))
	end
	return parts
end

-----------------------------------------------------------------------
-- serviceView(name)
--
-- Service: what points to it (its own links are in its frontmatter)
-----------------------------------------------------------------------
local function serviceView(name)
	return {
		section("Exposes", { "service", "hostname", "auth" },
			pageRows(sortByName(views.linkedTo("service", "exposedVia", name)), { "hostname", "auth" })),
		section("Logs in", { "service", "hostname" },
			pageRows(sortByName(views.linkedTo("service", "authVia", name)), { "hostname" })),
		section("Used by", { "name", "type" },
			pageRows(sortByName(views.linkedTo("component", "dependsOn", name)), { "type" })),
	}
end

-----------------------------------------------------------------------
-- storageView(name)
--
-- Storage: its stack, and where its data is copied to
-----------------------------------------------------------------------
local function storageView(name)
	local pages = itam.byName("component")
	local chain = backup.chain(name)
	local summary = backup.summary(name, chain, pages)
	local rows = {}
	for _, step in ipairs(chain) do
		table.insert(rows, { step.level, itam.link(step.from), itam.link(step.job),
			step.tool, step.schedule, itam.link(step.to) })
	end
	local parts = {}
	addDiagram(parts, "Stack", views.stack(name))
	table.insert(parts, section(
		"Backup chain: " .. summary.copies .. " copies, " .. summary.offsite .. " offsite",
		{ "level", "from", "job", "tool", "schedule", "to" }, rows))
	addDiagram(parts, "Backup diagram", (#chain > 0) and backup.diagram(name, chain, pages) or nil)
	return parts
end

-----------------------------------------------------------------------
-- lastNumber(ip)
--
-- "192.168.1.12-20" -> 12
-----------------------------------------------------------------------
local function lastNumber(ip)
	return tonumber(string.match(ip, "(%d+)[^%.]*$") or "") or 999
end

-----------------------------------------------------------------------
-- networkView(name, page)
--
-- Network: a diagram, the members (hosts first) and, on a LAN, every
-- address on it, including those of services on its hosts (macvlan
-- containers)
-----------------------------------------------------------------------
local function networkView(name, page)
	local parts, members, onNetwork = {}, views.linkedTo("component", "network", name), {}
	addDiagram(parts, "Diagram", views.network(name))
	local rows = {}
	for _, kind in ipairs({ "host", "service" }) do
		local pages = {}
		for _, member in ipairs(members) do
			onNetwork[member.name] = true
			if itam.hasTag(member, kind) then table.insert(pages, member) end
		end
		for _, member in ipairs(sortByType(pages, kind)) do
			table.insert(rows, { itam.link(member.name), kind, member.type })
		end
	end
	table.insert(parts, section("Members", { "name", "kind", "type" }, rows))

	if page.type == "lan" then
		local addresses = {}
		for _, other in ipairs(itam.pages("component")) do
			local onIt = onNetwork[other.name]
			for _, host in ipairs(itam.list(other.partOf)) do
				if onNetwork[itam.unlink(host)] then onIt = true end
			end
			if other.lanIp and onIt then
				for _, ip in ipairs(itam.list(other.lanIp)) do
					table.insert(addresses, { ip, itam.link(other.name), other.type, other.status })
				end
			end
		end
		table.sort(addresses, function(a, b) return lastNumber(a[1]) < lastNumber(b[1]) end)
		table.insert(parts, section("Addresses", { "address", "name", "type", "status" }, addresses))
	end
	return parts
end

-----------------------------------------------------------------------
-- policyView(name)
--
-- Policy: the storage that must meet it, and the jobs that implement
-- it
-----------------------------------------------------------------------
local function policyView(name)
	return {
		section("Storage under this policy", { "storage", "type", "copies", "offsite" },
			copyRows(sortByType(views.linkedTo("storage", "policies", name), "storage"), true)),
		section("Jobs implementing it", { "job", "type", "schedule" },
			pageRows(sortByType(views.linkedTo("job", "implements", name), "job"), { "type", "schedule" })),
	}
end

-----------------------------------------------------------------------
-- jobView(name, page)
--
-- Job: what it copies where
-----------------------------------------------------------------------
local function jobView(name, page)
	local rows = {}
	for _, copy in ipairs(itam.copies(page)) do
		table.insert(rows, { itam.link(copy.from), itam.link(copy.to) })
	end
	return { section("Copies", { "from", "to" }, rows) }
end

-----------------------------------------------------------------------
-- decisionView(name)
--
-- Decision: the objects it governs
-----------------------------------------------------------------------
local function decisionView(name)
	return {
		section("Governs", { "name", "type" },
			pageRows(sortByName(views.linkedTo("component", "decision", name)), { "type" })),
	}
end

-----------------------------------------------------------------------
-- viewsByTag
--
-- The first tag that matches decides the view
-----------------------------------------------------------------------
local viewsByTag = {
	{ tag = "host",    view = hostView },
	{ tag = "service", view = serviceView },
	{ tag = "storage", view = storageView },
	{ tag = "network", view = networkView },
	{ tag = "policy",  view = policyView },
	{ tag = "job",     view = jobView },
	{ tag = "dr",      view = decisionView },
}

-----------------------------------------------------------------------
-- views.page(name)
--
-- The view of any object page; the same call on every page
-----------------------------------------------------------------------
function views.page(name)
	local page = itam.page(name)
	if not page then return widget.markdownBlock("*Not indexed yet.*") end
	for _, entry in ipairs(viewsByTag) do
		if itam.hasTag(page, entry.tag) then return compose(entry.view(name, page)) end
	end
	return widget.markdownBlock("*No view for this kind of page.*")
end
