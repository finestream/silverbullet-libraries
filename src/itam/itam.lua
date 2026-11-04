-----------------------------------------------------------------------
-- Package itam
--
-- IT Asset Management: configuration, shared lists, helpers and tag
-- schemas
--
-- Three globals: `itam` (configuration, lists, helpers, schemas),
-- `backup` (the chain) and `views` (what pages call). Everything else
-- is local.
-----------------------------------------------------------------------
itam = {}

-----------------------------------------------------------------------
-- Configuration
--
-- Everything that is specific to one space lives under the `itam` key
-- of its CONFIG page (config.set { itam = {…} }). Every key is
-- optional; these are the defaults. The library reads them when it
-- needs them; a page never does.
-----------------------------------------------------------------------

itam.defaults = {
	-- Page prefixes under which the objects live; the views consider these pages only
	roots = { "Computer/" },
	-- Where the page templates create pages; the first root when not set
	pagePrefix = nil,
	-- The allowed `location` values (sites); an empty list allows any text
	sites = {},
	-- The group of the hosts of type external in the architecture diagram
	providers = "Providers",
	-- Per kind (host, service, storage, network, policy, job, auth), a list of
	-- values that replaces the default list of itam.types
	types = {},
	-- Decision records
	dr = {
		tagPage = nil,      -- the page the `dr` tag opens, e.g. the index of the decisions
		areas = {},         -- the allowed `area` values; an empty list allows any text
		deciders = "",      -- `deciders` of a new decision, e.g. "@me"
		owner = "",         -- `owner` of a new decision
		reviewDays = 180,   -- days after `lastReviewed` until a decision is due for review
	},
}

-----------------------------------------------------------------------
-- itam.config()
--
-- The configuration of this space merged over the defaults (`dr` one
-- level deep)
-----------------------------------------------------------------------
function itam.config()
	local set = config.get("itam", {}) or {}
	local cfg = {}
	for key, value in pairs(itam.defaults) do cfg[key] = value end
	for key, value in pairs(set) do
		if key ~= "dr" then cfg[key] = value end
	end
	cfg.dr = {}
	for key, value in pairs(itam.defaults.dr) do cfg.dr[key] = value end
	for key, value in pairs(set.dr or {}) do cfg.dr[key] = value end
	return cfg
end

-----------------------------------------------------------------------
-- itam.pagePrefix()
--
-- Where the page templates create pages, e.g. "Computer/"
-----------------------------------------------------------------------
function itam.pagePrefix()
	local cfg = itam.config()
	return cfg.pagePrefix or cfg.roots[1] or ""
end

-----------------------------------------------------------------------
-- itam.drDefault(field)
--
-- A default value for a new decision: "deciders" or "owner"
-----------------------------------------------------------------------
function itam.drDefault(field)
	return itam.config().dr[field] or ""
end

-----------------------------------------------------------------------
-- Shared lists
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- itam.types
--
-- Default `type` values per kind, and the `auth` values of a service;
-- the order is also the sort order in the views. A space replaces a
-- list with `types.<kind>`.
-----------------------------------------------------------------------
itam.types = {
	host    = { "server", "nas", "mac", "pc", "pi", "mobile", "appliance", "external", "unused" },
	service = { "container", "package", "system", "app", "external" },
	storage = { "hdd", "ssd", "sd-card", "usb-stick", "raid", "luks", "lvm-pv", "lvm-vg",
		"lvm-lv", "volume", "share", "folder", "repository", "cloud" },
	network = { "lan", "tailnet", "internet", "docker-bridge", "docker-macvlan" },
	policy  = { "backup", "snapshot", "retention" },
	job     = { "backup", "snapshot", "sync", "update", "test", "scrub", "script" },
	auth    = { "keycloak", "forward-auth", "own", "none", "n/a" },
}
-----------------------------------------------------------------------
-- itam.copyJobs
--
-- Job types that copy from source to target
-----------------------------------------------------------------------
itam.copyJobs = { backup = true, snapshot = true, sync = true }

-----------------------------------------------------------------------
-- itam.typesOf(kind)
--
-- The allowed values of a kind in this space: the configured list,
-- else the default
-----------------------------------------------------------------------
function itam.typesOf(kind)
	return itam.config().types[kind] or itam.types[kind] or {}
end

-----------------------------------------------------------------------
-- itam.hint(what)
--
-- The allowed values of a list as text, for the comments of the page
-- templates: "server, nas, …", or "free text" for a list the space
-- left empty
-----------------------------------------------------------------------
function itam.hint(what)
	local values
	if what == "sites" then
		values = itam.config().sites
	elseif what == "areas" then
		values = itam.config().dr.areas
	else
		values = itam.typesOf(what)
	end
	if #values == 0 then return "free text" end
	return table.concat(values, ", ")
end

-----------------------------------------------------------------------
-- Helpers, used by all blocks
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- itam.list(value)
--
-- A frontmatter value as a list: nil -> {}, "x" -> {"x"}, {...} ->
-- {...}
-----------------------------------------------------------------------
function itam.list(value)
	if value == nil then return {} end
	if type(value) == "table" then return value end
	return { value }
end

-----------------------------------------------------------------------
-- itam.oneOf(value, values)
--
-- Whether `value` is one of `values`; an empty list accepts anything
-----------------------------------------------------------------------
function itam.oneOf(value, values)
	if #values == 0 then return true end
	for _, v in ipairs(values) do
		if v == value then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- itam.allOf(value, values)
--
-- Every value of a list (or the single value) is one of `values`
-----------------------------------------------------------------------
function itam.allOf(value, values)
	for _, v in ipairs(itam.list(value)) do
		if not itam.oneOf(v, values) then return false end
	end
	return true
end

-----------------------------------------------------------------------
-- itam.unlink(value)
--
-- "[[Some/Page]]" -> "Some/Page"
-----------------------------------------------------------------------
function itam.unlink(value)
	if type(value) ~= "string" then return nil end
	return string.match(value, "^%[%[(.-)%]%]$") or value
end

-----------------------------------------------------------------------
-- itam.link(name)
--
-- "Some/Page" -> "[[Some/Page]]"
-----------------------------------------------------------------------
function itam.link(name)
	return "[[" .. name .. "]]"
end

-----------------------------------------------------------------------
-- itam.short(name)
--
-- "Computer/Storage/volume1" -> "volume1"
-----------------------------------------------------------------------
function itam.short(name)
	return string.match(name, "[^/]+$") or name
end

-----------------------------------------------------------------------
-- itam.hasTag(page, tagName)
--
-- Whether a page carries the tag.
-----------------------------------------------------------------------
function itam.hasTag(page, tagName)
	for _, t in ipairs(itam.list(page.tags)) do
		if t == tagName then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- itam.inScope(name)
--
-- Pages of this documentation: under one of the configured roots
-----------------------------------------------------------------------
function itam.inScope(name)
	for _, root in ipairs(itam.config().roots) do
		if string.sub(name, 1, #root) == root then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- itam.pages(tagName)
--
-- The only two queries: all pages with a tag, and one page by its name
-----------------------------------------------------------------------
function itam.pages(tagName)
	return query[[from index.pages(tagName)]]
end

-----------------------------------------------------------------------
-- itam.page(name)
--
-- One page by its name; nil when it is not indexed.
-----------------------------------------------------------------------
function itam.page(name)
	local found = query[[from p = index.pages() where p.name == name]]
	return found[1]
end

-----------------------------------------------------------------------
-- itam.byName(tagName)
--
-- Pages with a tag, keyed by name
-----------------------------------------------------------------------
function itam.byName(tagName)
	local byName = {}
	for _, page in ipairs(itam.pages(tagName)) do byName[page.name] = page end
	return byName
end

-----------------------------------------------------------------------
-- itam.copies(job)
--
-- The copies a job makes, as { from, to } page names. A snapshot keeps
-- its copy on the same storage, whatever else is listed as target.
-----------------------------------------------------------------------
function itam.copies(job)
	local copies = {}
	if not itam.copyJobs[job.type] then return copies end
	for _, source in ipairs(itam.list(job.source)) do
		local targets = (job.type == "snapshot") and { source } or itam.list(job.target)
		for _, target in ipairs(targets) do
			table.insert(copies, { from = itam.unlink(source), to = itam.unlink(target) })
		end
	end
	return copies
end

-----------------------------------------------------------------------
-- itam.flowchart()
--
-- A Mermaid flowchart, built box by box: every box opens its page; a
-- box can sit in a named group (drawn as a subgraph). Groups come
-- first, then loose boxes, then edges.
-----------------------------------------------------------------------
function itam.flowchart()
	local chart = { groups = {}, groupOrder = {}, loose = {}, edges = {}, drawn = {}, size = 0 }

	function chart.box(name, label, group, shape)
		if chart.drawn[name] then return end
		chart.drawn[name] = true
		chart.size = chart.size + 1
		local into = chart.loose
		if group then
			if not chart.groups[group] then
				chart.groups[group] = {}
				table.insert(chart.groupOrder, group)
			end
			into = chart.groups[group]
		end
		table.insert(into, { kind = "node", id = name, label = label or itam.short(name), shape = shape })
		table.insert(into, { kind = "click", id = name, target = name })
	end

	function chart.edge(from, to, label)
		table.insert(chart.edges, { kind = "edge", from = from, to = to, label = label, arrow = true })
	end

	-- `order` (optional) lists the groups to draw first
	function chart.render(direction, order)
		local elements, placed = {}, {}
		local function addGroup(group)
			if chart.groups[group] and not placed[group] then
				placed[group] = true
				table.insert(elements, {
					kind = "subgraph", id = "group_" .. group, label = itam.short(group),
					elements = chart.groups[group],
				})
			end
		end
		for _, group in ipairs(order or {}) do addGroup(group) end
		for _, group in ipairs(chart.groupOrder) do addGroup(group) end
		for _, element in ipairs(chart.loose) do table.insert(elements, element) end
		for _, edge in ipairs(chart.edges) do table.insert(elements, edge) end
		return mermaid.diagram { type = "flowchart", direction = direction, elements = elements }
	end

	return chart
end

-----------------------------------------------------------------------
-- Tag schemas
--
-- One tag.define per object type. Each lists only its own fields;
-- `object` adds the fields every object may carry (`decision`,
-- `lastReviewed`). The values of `type`, `auth`, `location` and `area`
-- come from the configuration, so the schema holds them as text and
-- `validate` checks them when a page is indexed; the enum of a list
-- that is known when this script loads is offered as well, for
-- completion in the editor.
-----------------------------------------------------------------------

local text  = schema.nullable("string")         -- optional free text
local link  = schema.nullable("string")         -- one "[[page]]"
local links = schema.nullableArray("string")    -- a list of "[[page]]"
local linkOrLinks = { anyOf = {                 -- one "[[page]]", or a list of them
	{ type = "string" }, { type = "array", items = { type = "string" } }, { type = "null" },
} }
local flag  = schema.nullable("boolean")
local number = schema.nullable("number")

-----------------------------------------------------------------------
-- oneOf(values)
--
-- One value from a fixed list.
-----------------------------------------------------------------------
local function oneOf(values)
	return { type = "string", enum = values }
end

-----------------------------------------------------------------------
-- configured(values)
--
-- One value of a configured list: an enum when the list is known now,
-- else text
-----------------------------------------------------------------------
local function configured(values)
	if #values == 0 then return { type = "string" } end
	return oneOf(values)
end

-----------------------------------------------------------------------
-- nullableConfigured(values)
--
-- Like configured(values), and the field may be left out.
-----------------------------------------------------------------------
local function nullableConfigured(values)
	if #values == 0 then return text end
	return schema.nullable(oneOf(values))
end

-----------------------------------------------------------------------
-- oneOrMore(values)
--
-- One value, or a list of them.
-----------------------------------------------------------------------
local function oneOrMore(values)
	local one = configured(values)
	return { anyOf = { one, { type = "array", items = one } } }
end

-----------------------------------------------------------------------
-- object(required, properties)
--
-- An object schema: its own fields, the fields every object may carry,
-- what is required
-----------------------------------------------------------------------
local function object(required, properties)
	properties.decision     = links               -- governing decision(s)
	properties.lastReviewed = text                -- YYYY-MM-DD
	return { type = "object", properties = properties, required = required }
end

-----------------------------------------------------------------------
-- icon(name)
--
-- A tag transform that decorates the page with the icon `name`.
-----------------------------------------------------------------------
local function icon(name)
	return function(o) o.pageDecoration = { icon = name } return o end
end

-----------------------------------------------------------------------
-- checkType(kind, value)
--
-- "type must be one of server, nas, …" or nil when `value` is allowed
-- for `kind`
-----------------------------------------------------------------------
local function checkType(kind, value)
	local allowed = itam.typesOf(kind)
	if not itam.allOf(value, allowed) then
		return "type must be one of " .. table.concat(allowed, ", ")
	end
end

-----------------------------------------------------------------------
-- checkSite(value)
--
-- "location must be one of …", or nil when `value` is allowed in this
-- space.
-----------------------------------------------------------------------
local function checkSite(value)
	local sites = itam.config().sites
	if value ~= nil and not itam.oneOf(value, sites) then
		return "location must be one of " .. table.concat(sites, ", ")
	end
end

-----------------------------------------------------------------------
-- Tag component
--
-- Component: carried by every object page next to its own tag, so that
-- all objects can be queried at once; no schema and no decoration of
-- its own
-----------------------------------------------------------------------
tag.define {
	name = "component",
}

-----------------------------------------------------------------------
-- Tag host
--
-- Host: a machine or device, the third-party providers (type
-- external), or a free address on the LAN (type unused)
-----------------------------------------------------------------------
tag.define {
	name = "host",
	schema = object({ "type", "network", "status" }, {
		type     = configured(itam.typesOf("host")),
		role     = text,
		location = nullableConfigured(itam.config().sites), -- every host except external
		network  = links,
		platform = text,                            -- OS and hardware
		lanIp    = schema.nullableArray("string"),  -- fixed or reserved addresses
		status   = oneOf { "active", "on-demand", "parked", "free" },
	}),
	validate = function(o)
		local bad = checkType("host", o.type) or checkSite(o.location)
		if bad then return bad end
		if o.type ~= "external" and not o.location then return "A host needs a location" end
		if o.type == "unused" then
			if not o.lanIp then return "An unused reservation needs lanIp" end
		elseif not o.role then
			return "A host needs a role"
		end
	end,
	transform = function(o)
		local icons = { unused = "circle", external = "cloud", mobile = "smartphone" }
		o.pageDecoration = { icon = icons[o.type] or "server" }
		return o
	end,
}

-----------------------------------------------------------------------
-- Tag service
--
-- Service: something that runs and offers a function
-----------------------------------------------------------------------
tag.define {
	name = "service",
	schema = object({ "type", "partOf", "purpose", "auth", "status" }, {
		type       = oneOrMore(itam.typesOf("service")), -- a list when it runs differently per host
		partOf     = linkOrLinks,                   -- the host, or a list of hosts
		purpose    = text,
		provider   = text,                          -- for type external
		hostname   = text,                          -- e.g. notes.example.org
		lanIp      = schema.nullableArray("string"),-- macvlan containers
		auth       = configured(itam.typesOf("auth")),
		network    = links,
		exposedVia = links,                         -- the reverse proxy
		authVia    = links,                         -- the login service
		dependsOn  = links,
		status     = oneOf { "active", "on-demand", "parked" },
	}),
	validate = function(o)
		local bad = checkType("service", o.type)
		if bad then return bad end
		if not itam.oneOf(o.auth, itam.typesOf("auth")) then
			return "auth must be one of " .. table.concat(itam.typesOf("auth"), ", ")
		end
	end,
	transform = icon("box"),
}

local date = { type = "string", pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" } -- YYYY-MM-DD

-----------------------------------------------------------------------
-- Tag domain
--
-- An extra tag on a service of type external (one page per domain);
-- only the fields a domain adds, the service schema checks the rest.
-----------------------------------------------------------------------
tag.define {
	name = "domain",
	schema = {
		type = "object",
		properties = {
			registered = date,                        -- from the registry (RDAP)
			renewal    = date,                        -- end of the paid period
			mail       = text,                        -- who handles mail for the domain
		},
		required = { "registered", "renewal" },
	},
}

-----------------------------------------------------------------------
-- Tag network
--
-- Network: a LAN, a VPN, the internet, or a Docker network on a host
-----------------------------------------------------------------------
tag.define {
	name = "network",
	schema = object({ "type" }, {
		type     = configured(itam.typesOf("network")),
		partOf   = link,                            -- the host, for Docker networks
		cidr     = text,
		location = nullableConfigured(itam.config().sites), -- for type lan
	}),
	validate = function(o)
		return checkType("network", o.type) or checkSite(o.location)
	end,
	transform = icon("share-2"),
}

-----------------------------------------------------------------------
-- Tag storage
--
-- Storage: anything that holds data, from the disk up to a share or a
-- cloud account
-----------------------------------------------------------------------
tag.define {
	name = "storage",
	schema = object({ "type", "status" }, {
		type       = configured(itam.typesOf("storage")),
		partOf     = linkOrLinks,                   -- the host, or a list for a replica
		on         = links,                         -- the layer(s) below, one per host for a replica
		policies   = links,
		capacity   = text,
		redundancy = text,                          -- raid1, raid5, single
		encrypted  = flag,
		filesystem = text,
		path       = text,
		location   = nullableConfigured(itam.config().sites), -- where loose storage is kept
		-- Physical devices (SD cards, USB sticks)
		brand        = text,
		model        = text,
		format       = text,                        -- e.g. SDHC
		speedClass   = text,                        -- e.g. C10
		uhs          = number,                      -- UHS speed class, e.g. 1
		busInterface = text,                        -- UHS bus interface, e.g. I
		appClass     = text,                        -- e.g. A1
		writeSpeed   = number,                      -- measured, MB/s
		readSpeed    = number,                      -- measured, MB/s
		inventoryId  = number,                      -- number on the label
		status     = oneOf { "active", "spare", "retired" },
	}),
	validate = function(o)
		local bad = checkType("storage", o.type) or checkSite(o.location)
		if bad then return bad end
		if not o.partOf and not o.location then
			return "Storage that is part of no host needs a location"
		end
	end,
	transform = icon("hard-drive"),
}

-----------------------------------------------------------------------
-- Tag policy
--
-- Policy: a rule that storage must meet
-----------------------------------------------------------------------
tag.define {
	name = "policy",
	schema = object({ "type" }, {
		type               = configured(itam.typesOf("policy")),
		copies             = number,              -- the original included
		offsite            = flag,
		frequency          = text,
		retentionSnapshots = text,
		retentionLocal     = text,
		retentionOffsite   = text,
	}),
	validate = function(o)
		return checkType("policy", o.type)
	end,
	transform = icon("shield"),
}

-----------------------------------------------------------------------
-- Tag job
--
-- Job: something that runs on a schedule or at boot on one host
-----------------------------------------------------------------------
tag.define {
	name = "job",
	schema = object({ "type", "partOf", "schedule" }, {
		type       = configured(itam.typesOf("job")),
		partOf     = link,                          -- the host it runs on
		tool       = text,
		schedule   = text,                          -- e.g. "daily 01:02", "every 4 hours", "boot"
		source     = links,                         -- copy jobs: storage copied from
		target     = links,                         -- copy jobs: storage copied to
		implements = links,                         -- the policy it fulfils
		encrypted  = flag,
		versions   = text,
	}),
	validate = function(o)
		local bad = checkType("job", o.type)
		if bad then return bad end
		if itam.copyJobs[o.type] and not o.source then
			return "A " .. o.type .. " job needs a source"
		end
		if (o.type == "backup" or o.type == "sync") and not o.target then
			return "A " .. o.type .. " job needs a target"
		end
	end,
	transform = icon("clock"),
}
