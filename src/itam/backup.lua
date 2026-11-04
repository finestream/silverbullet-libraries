
-- Backup chain -------------------------------------------------------------------------
--
-- Three functions, all starting from a storage page and following the copies of the
-- copy jobs (itam.copies) from source to target. `rows` and `pages` are optional: a
-- view that needs several of them computes the chain and the component pages once.
backup = backup or {}

-- Every copy step from `start` on, depth first, each storage followed once.
-- A step: level, from, job, tool, schedule, to. `jobs` defaults to all job pages.
function backup.chain(start, jobs)
  local stepsFrom = {}
  for _, job in ipairs(jobs or itam.pages("job")) do
    for _, copy in ipairs(itam.copies(job)) do
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

-- One site per copy: a storage on several hosts (a replica) has one copy per host.
-- "external" for a host of type external, else the host's location; storage in
-- no host has its own location.
local function sitesOf(name, pages)
  local page, sites = pages[name], {}
  for _, value in ipairs(itam.list(page and page.partOf)) do
    local host = pages[itam.unlink(value)]
    if host and host.type == "external" then
      table.insert(sites, "external")
    else
      table.insert(sites, (host and host.location) or "unknown")
    end
  end
  if #sites == 0 then table.insert(sites, (page and page.location) or "unknown") end
  return sites
end

-- Copies in the chain (the original included), and how many sit at another site.
-- `rows` and `pages` are optional, to reuse a chain or the component pages.
function backup.summary(start, rows, pages)
  rows = rows or backup.chain(start)
  pages = pages or itam.byName("component")
  local home = sitesOf(start, pages)[1]
  local copies, offsite, counted = 0, 0, {}
  local function count(name)
    if counted[name] then return end            -- a snapshot is no new copy
    counted[name] = true
    for _, site in ipairs(sitesOf(name, pages)) do
      copies = copies + 1
      if site ~= home then offsite = offsite + 1 end
    end
  end
  count(start)
  for _, row in ipairs(rows) do count(row.to) end
  return { storage = start, copies = copies, offsite = offsite }
end

-- The chain as a diagram: storage grouped by its (first) host, jobs as labelled arrows
function backup.diagram(start, rows, pages)
  rows = rows or backup.chain(start)
  pages = pages or itam.byName("component")
  local chart = itam.flowchart()

  local function box(name)
    local hosts = itam.list(pages[name] and pages[name].partOf)
    local label = itam.short(name)
    if #hosts > 1 then                          -- a replica: drawn with its first host
      local others = {}
      for i = 2, #hosts do table.insert(others, itam.short(itam.unlink(hosts[i]))) end
      label = label .. " (also on " .. table.concat(others, ", ") .. ")"
    end
    chart.box(name, label, itam.unlink(hosts[1]) or "Other", "rounded")
  end

  box(start)
  for _, row in ipairs(rows) do
    box(row.from)
    box(row.to)
    local label = (row.tool or itam.short(row.job)) .. (row.schedule and (", " .. row.schedule) or "")
    chart.edge(row.from, row.to, label)
  end
  return chart.render("LR")
end
