
-----------------------------------------------------------------------
-- Package ITAM.backup
--
-- Backup chain.
--
-- Three functions, all starting from a storage page and following the
-- copies of the copy jobs (ITAM.copies) from source to target. `rows`
-- and `pages` are optional: a view that needs several of them computes
-- the chain and the component pages once.
-----------------------------------------------------------------------
ITAM.backup = {}

-----------------------------------------------------------------------
-- ITAM.backup.chain(start, jobs)
--
-- Every copy step from `start` on, depth first, each storage followed
-- once. A step: level, from, job, tool, schedule, to. `jobs` defaults
-- to all job pages.
-----------------------------------------------------------------------
function ITAM.backup.chain(start, jobs)
	local stepsFrom = {}
	for _, job in ipairs(jobs or ITAM.pages("job")) do
		for _, copy in ipairs(ITAM.copies(job)) do
			stepsFrom[copy.from] = stepsFrom[copy.from] or {}
			table.insert(stepsFrom[copy.from], { job = job, to = copy.to })
		end
	end

	local rows, visited = {}, {}
	local function follow(storage, level)
		if visited[storage] then return end
		visited[storage] = true
		for _, step in ipairs(stepsFrom[storage] or {}) do
			table.insert(rows, {
				level = level, from = storage, job = step.job.name,
				tool = step.job.tool, schedule = step.job.schedule, to = step.to,
			})
			follow(step.to, level + 1)
		end
	end
	follow(start, 0)
	return rows
end

-----------------------------------------------------------------------
-- sitesOf(name, pages)
--
-- One site per copy: a storage on several hosts (a replica) has one
-- copy per host. "external" for a host of type external, else the
-- host's location; storage in no host has its own location.
-----------------------------------------------------------------------
local function sitesOf(name, pages)
	local page, sites = pages[name], {}
	for _, value in ipairs(ITAM.list(page and page.partOf)) do
		local host = pages[ITAM.unlink(value)]
		if host and host.type == "external" then
			table.insert(sites, "external")
		else
			table.insert(sites, (host and host.location) or "unknown")
		end
	end
	if #sites == 0 then table.insert(sites, (page and page.location) or "unknown") end
	return sites
end

-----------------------------------------------------------------------
-- ITAM.backup.summary(start, rows, pages)
--
-- Copies in the chain (the original included), and how many are
-- offsite: at another site than the original, or on a host of type
-- external, the original itself included. `rows` and `pages` are
-- optional, to reuse a chain or the component pages.
-----------------------------------------------------------------------
function ITAM.backup.summary(start, rows, pages)
	rows = rows or ITAM.backup.chain(start)
	pages = pages or ITAM.byName("component")
	local home = sitesOf(start, pages)[1]
	local copies, offsite, counted = 0, 0, {}
	local function count(name)
		if counted[name] then return end            -- a snapshot is no new copy
		counted[name] = true
		for _, site in ipairs(sitesOf(name, pages)) do
			copies = copies + 1
			if site == "external" or site ~= home then offsite = offsite + 1 end
		end
	end
	count(start)
	for _, row in ipairs(rows) do count(row.to) end
	return { storage = start, copies = copies, offsite = offsite }
end

-----------------------------------------------------------------------
-- ITAM.backup.diagram(start, rows, pages)
--
-- The chain as a diagram: storage grouped by its (first) host, jobs as
-- labelled arrows
-----------------------------------------------------------------------
function ITAM.backup.diagram(start, rows, pages)
	rows = rows or ITAM.backup.chain(start)
	pages = pages or ITAM.byName("component")
	local chart = ITAM.flowchart()

	local function box(name)
		local hosts = ITAM.list(pages[name] and pages[name].partOf)
		local label = ITAM.short(name)
		if #hosts > 1 then                          -- a replica: drawn with its first host
			local others = {}
			for i = 2, #hosts do table.insert(others, ITAM.short(ITAM.unlink(hosts[i]))) end
			label = label .. " (also on " .. table.concat(others, ", ") .. ")"
		end
		chart.box(name, label, ITAM.unlink(hosts[1]) or "Other", "rounded")
	end

	box(start)
	for _, row in ipairs(rows) do
		box(row.from)
		box(row.to)
		local label = (row.tool or ITAM.short(row.job)) .. (row.schedule and (", " .. row.schedule) or "")
		chart.edge(row.from, row.to, label)
	end
	return chart.render("LR")
end
