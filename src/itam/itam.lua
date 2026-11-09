-- priority: -10
-----------------------------------------------------------------------
-- Package ITAM
--
-- ITAM (IT asset management): configuration, shared lists, helpers and tag
-- schemas
--
-- One global, `ITAM` (configuration, lists, helpers, schemas), with
-- `ITAM.backup` (the chain) and `ITAM.views` (what pages call).
-- Everything else is local.
--
-- The priority on the first line loads this script after every script
-- without a priority, so the configuration is complete whatever page it
-- is on when the definitions and schemas below are built from it. All
-- fragments of the library are one script, so their order is the build
-- order.
-----------------------------------------------------------------------
ITAM = {}

-----------------------------------------------------------------------
-- Configuration
--
-- Everything that is specific to one space lives under the `itam` key
-- of its CONFIG page (config.set { itam = {…} }). Every key is
-- optional; these are the defaults. The library reads them when it
-- needs them; a page never does.
-----------------------------------------------------------------------

-- The default `status` lifecycle of every component kind (ITAM.defaults.statuses)
local componentStatuses = { "planned", "implementation", "active", "on-demand", "spare", "retired" }

ITAM.defaults = {
	-- Page prefixes under which the objects live; the views consider these pages only
	roots = { "Computer/" },
	-- Where the page templates create pages; the first root when not set
	pagePrefix = nil,
	-- The allowed `location` values (sites); an empty list allows any text
	sites = {},
	-- The group of the hosts of type external in the architecture diagram
	providers = "Providers",
	-- Per kind (host, service, storage, network, policy, job, auth), a list of
	-- definitions that replaces the default list of ITAM.types
	types = {},
	-- Per kind (host, service, storage, network, policy, job), the allowed
	-- `status` values: a list (the field is required and takes one of them),
	-- a table { values = {…}, optional = true } (the field may be left out),
	-- or false (the kind has no `status`); an empty list of values allows
	-- any text. A kind left out keeps its default: one lifecycle for every
	-- component.
	statuses = {
		host    = componentStatuses,
		service = componentStatuses,
		storage = componentStatuses,
		network = componentStatuses,
		policy  = componentStatuses,
		job     = componentStatuses,
	},
	-- Decision records
	dr = {
		tagPage = nil,      -- the page the `dr` tag opens, e.g. the index of the decisions
		areas = {},         -- the allowed `area` values; an empty list allows any text
		deciders = "",      -- `deciders` of a new decision, e.g. "@me"
		owner = "",         -- `owner` of a new decision
		reviewDays = 180,   -- days after `lastReviewed` until a decision is due for review
		-- The lifecycle: the `status` values of a decision in their order; the
		-- first is what a new decision gets. An entry is a name, or a table
		-- with a name and properties: `dot` (the page decoration and the
		-- marker in the graph), `active` (the decision is in force or on its
		-- way there, so it is due for review), `provisional` (binding but
		-- still edited, listed by drProvisional). An entry named like a
		-- default keeps that default's properties. An empty list allows any
		-- text.
		statuses = {
			{ name = "proposed",    dot = "🟡", active = true },
			{ name = "provisional", dot = "🔵", active = true, provisional = true },
			{ name = "accepted",    dot = "🟢", active = true },
			{ name = "superseded",  dot = "⚪" },
			{ name = "deprecated",  dot = "🟠" },
			{ name = "rejected",    dot = "🔴" },
		},
	},
}

-----------------------------------------------------------------------
-- listOf(value)
--
-- A configured list as a Lua list: nil -> {}, "x" -> {"x"}, {...} ->
-- a copy. config.get returns an empty list (`sites = {}`) as an empty
-- object, on which `#` raises "attempt to get length of a table
-- value"; the copy has a length.
-----------------------------------------------------------------------
local function listOf(value)
	local list = {}
	if type(value) == "table" then
		for _, entry in ipairs(value) do table.insert(list, entry) end
	elseif value ~= nil then
		table.insert(list, value)
	end
	return list
end

-----------------------------------------------------------------------
-- statusSpec(entries)
--
-- A configured `statuses.<kind>` entry as { values, optional }: a list
-- of values, a table with `values` and `optional`, or false / nil for
-- a kind without `status` (-> nil). `values` is always a Lua list.
--
-- A list from config.get is a JS array, and `entries.values` on it is
-- the array's method, not nil: the table form is recognised only when
-- the entry has no first element and `values` is set to something
-- other than a function (a list or a single value), or `optional` is
-- a boolean.
-----------------------------------------------------------------------
local function statusSpec(entries)
	if entries == nil or entries == false then return nil end
	if type(entries) ~= "table" then return { values = listOf(entries), optional = false } end
	local values = entries.values
	if type(values) == "function" then values = nil end
	if entries[1] == nil and (values ~= nil or type(entries.optional) == "boolean") then
		return { values = listOf(values), optional = entries.optional == true }
	end
	return { values = listOf(entries), optional = false }
end

-----------------------------------------------------------------------
-- ITAM.config()
--
-- The configuration of this space merged over the defaults (`statuses`
-- per kind, `dr` one level deep). Every list (`roots`, `sites`,
-- `types.<kind>`, `dr.areas`, `dr.statuses`) comes back as a Lua list,
-- also when the space left it empty, so the callers may take its
-- length; `statuses.<kind>` comes back as { values, optional }, or nil
-- for a kind without `status`.
-----------------------------------------------------------------------
function ITAM.config()
	local set = config.get("itam", {}) or {}
	local cfg = {}
	for key, value in pairs(ITAM.defaults) do cfg[key] = value end
	for key, value in pairs(set) do
		if key ~= "dr" and key ~= "statuses" then cfg[key] = value end
	end
	cfg.roots = listOf(cfg.roots)
	cfg.sites = listOf(cfg.sites)
	local types = {}
	for kind, entries in pairs(cfg.types or {}) do types[kind] = listOf(entries) end
	cfg.types = types
	cfg.statuses = {}
	for kind, entries in pairs(ITAM.defaults.statuses) do cfg.statuses[kind] = statusSpec(entries) end
	for kind, entries in pairs(set.statuses or {}) do cfg.statuses[kind] = statusSpec(entries) end
	cfg.dr = {}
	for key, value in pairs(ITAM.defaults.dr) do cfg.dr[key] = value end
	for key, value in pairs(set.dr or {}) do cfg.dr[key] = value end
	cfg.dr.areas = listOf(cfg.dr.areas)
	cfg.dr.statuses = listOf(cfg.dr.statuses)
	return cfg
end

-----------------------------------------------------------------------
-- ITAM.pagePrefix()
--
-- Where the page templates create pages, e.g. "Computer/"
-----------------------------------------------------------------------
function ITAM.pagePrefix()
	local cfg = ITAM.config()
	return cfg.pagePrefix or cfg.roots[1] or ""
end

-----------------------------------------------------------------------
-- ITAM.drDefault(field)
--
-- A default value for a new decision: "deciders" or "owner"
-----------------------------------------------------------------------
function ITAM.drDefault(field)
	return ITAM.config().dr[field] or ""
end

-----------------------------------------------------------------------
-- Shared lists
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- ITAM.types
--
-- Default `type` values per kind, and the `auth` values of a service;
-- the order is also the sort order in the views. A space replaces a
-- list with `types.<kind>`.
--
-- An entry is a name, or a table with a name and properties. The
-- properties of a job type: `copy` (counts as a copy from source to
-- target), `inPlace` (the copy stays on the source, so there is no
-- target) and `policy` (the policy type that governs it).
-----------------------------------------------------------------------
ITAM.types = {
	host    = { "server", "nas", "mac", "pc", "pi", "mobile", "appliance", "external", "unused" },
	service = { "container", "package", "system", "app", "external" },
	storage = { "hdd", "ssd", "sd-card", "usb-stick", "raid", "luks", "lvm-pv", "lvm-vg",
		"lvm-lv", "volume", "share", "folder", "repository", "cloud" },
	network = { "lan", "tailnet", "internet", "docker-bridge", "docker-macvlan" },
	policy  = { "backup", "snapshot", "retention" },
	job     = {
		{ name = "backup", copy = true, policy = "backup" },
		{ name = "snapshot", copy = true, inPlace = true, policy = "snapshot" },
		{ name = "sync", copy = true, policy = "backup" },
		"update", "test", "scrub", "script",
	},
	auth    = { "keycloak", "forward-auth", "own", "none", "n/a" },
}
-----------------------------------------------------------------------
-- definitionsOf(defaultEntries, entries)
--
-- The configured `entries` (or the defaults when nil) as definitions,
-- in their order: a name, or a table with a name and properties. An
-- entry named like a default starts from that default's properties,
-- so a space that lists "backup" as a name keeps what a backup is, and
-- "provisional" keeps its dot. A table without a name defines nothing.
-- Shared by the types (ITAM.types[kind]) and the decision lifecycle
-- (ITAM.defaults.dr.statuses).
-----------------------------------------------------------------------
local function definitionsOf(defaultEntries, entries)
	local defaults, definitions = {}, {}
	for _, entry in ipairs(defaultEntries) do
		if type(entry) == "table" then defaults[entry.name] = entry end
	end
	for _, entry in ipairs(entries or defaultEntries) do
		local isTable = type(entry) == "table"
		local name = entry
		if isTable then name = entry.name end
		if name then
			local definition = { name = name }
			for key, value in pairs(defaults[name] or {}) do definition[key] = value end
			if isTable then
				for key, value in pairs(entry) do definition[key] = value end
			end
			table.insert(definitions, definition)
		end
	end
	return definitions
end

-----------------------------------------------------------------------
-- buildTypes()
--
-- The types of this space, per kind: `names` in their order and
-- `byName`. A policy type that a job type names is always a policy
-- type, added after the configured ones, so that overriding one of the
-- two lists cannot break the other.
-----------------------------------------------------------------------
local function buildTypes()
	local configured = ITAM.config().types
	local built = {}
	for kind, _ in pairs(ITAM.types) do
		local definitions = definitionsOf(ITAM.types[kind], configured[kind])
		built[kind] = { names = {}, byName = {} }
		for _, definition in ipairs(definitions) do
			table.insert(built[kind].names, definition.name)
			built[kind].byName[definition.name] = definition
		end
	end
	for _, name in ipairs(built.job.names) do
		local policy = built.job.byName[name].policy
		if policy and not built.policy.byName[policy] then
			table.insert(built.policy.names, policy)
			built.policy.byName[policy] = { name = policy }
		end
	end
	return built
end

local builtTypes = buildTypes()

-- The `status` specs of this space per kind, read when the library
-- loads, as the types are (ITAM.statusOf)
local builtStatuses = ITAM.config().statuses

-----------------------------------------------------------------------
-- ITAM.typesOf(kind)
--
-- The allowed values of a kind in this space, as names: the configured
-- list, else the default. Read when the library loads, as the schemas
-- are.
-----------------------------------------------------------------------
function ITAM.typesOf(kind)
	local built = builtTypes[kind]
	return built and built.names or {}
end

-----------------------------------------------------------------------
-- ITAM.definitionOf(kind, name)
--
-- The definition of one type of a kind, with its properties; an empty
-- table for a type that is not defined
-----------------------------------------------------------------------
function ITAM.definitionOf(kind, name)
	local built = builtTypes[kind]
	return built and built.byName[name] or {}
end

-----------------------------------------------------------------------
-- buildDrStatuses()
--
-- The lifecycle of a decision in this space: `names` in their order
-- and `byName` with the properties of each (`dot`, `active`,
-- `provisional`), merged with the defaults by definitionsOf.
-----------------------------------------------------------------------
local function buildDrStatuses()
	local names, byName = {}, {}
	for _, definition in ipairs(definitionsOf(ITAM.defaults.dr.statuses, ITAM.config().dr.statuses)) do
		table.insert(names, definition.name)
		byName[definition.name] = definition
	end
	return names, byName
end

local drStatusNames, drStatusByName = buildDrStatuses()

-----------------------------------------------------------------------
-- ITAM.drStatuses, ITAM.drDots, ITAM.drActive
--
-- The lifecycle of a decision as the views use it: the `status` values
-- in their order, the dot of each value, and the values that count as
-- active (due for review). Read when the library loads, as the schemas
-- are.
-----------------------------------------------------------------------
ITAM.drStatuses = drStatusNames
ITAM.drDots = {}
ITAM.drActive = {}
for _, name in ipairs(drStatusNames) do
	local definition = drStatusByName[name]
	if definition.dot then ITAM.drDots[name] = definition.dot end
	if definition.active then ITAM.drActive[name] = true end
end

-----------------------------------------------------------------------
-- ITAM.drStatusOf(name)
--
-- The definition of one `status` value of a decision, with its
-- properties; an empty table for a value that is not defined
-----------------------------------------------------------------------
function ITAM.drStatusOf(name)
	return drStatusByName[name] or {}
end

-----------------------------------------------------------------------
-- ITAM.statusOf(kind)
--
-- The `status` field of a kind in this space, as { values, optional }:
-- `values` the allowed values in their order (empty: any text), the
-- first of them what a new page gets; `optional` whether the field may
-- be left out. nil for a kind without `status`. "dr" answers with the
-- lifecycle of a decision. Read when the library loads, as the types
-- are: a change to CONFIG needs System: Reload.
-----------------------------------------------------------------------
function ITAM.statusOf(kind)
	if kind == "dr" then return { values = ITAM.drStatuses, optional = false } end
	return builtStatuses[kind]
end

-----------------------------------------------------------------------
-- ITAM.statusLine(kind)
--
-- The `status` line of a page template, with the allowed values as a
-- comment: "status: planned  # planned, implementation, active, …";
-- "status:  # free text" for a kind that allows any text; "" for a
-- kind without `status`, so that the template keeps an empty line in
-- its place.
-----------------------------------------------------------------------
function ITAM.statusLine(kind)
	local spec = ITAM.statusOf(kind)
	if not spec then return "" end
	local hint = "free text"
	if #spec.values > 0 then hint = table.concat(spec.values, ", ") end
	if spec.optional then hint = hint .. "; may be left out" end
	local value = ""
	if spec.values[1] then value = " " .. spec.values[1] end
	return "status:" .. value .. "  # " .. hint
end

-----------------------------------------------------------------------
-- ITAM.hint(what)
--
-- The allowed values of a list as text, for the comments of the page
-- templates: "server, nas, …", or "free text" for a list the space
-- left empty
-----------------------------------------------------------------------
function ITAM.hint(what)
	local values
	if what == "sites" then
		values = ITAM.config().sites
	elseif what == "areas" then
		values = ITAM.config().dr.areas
	else
		values = ITAM.typesOf(what)
	end
	if #values == 0 then return "free text" end
	return table.concat(values, ", ")
end

-----------------------------------------------------------------------
-- Helpers, used by all blocks
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- ITAM.list(value)
--
-- A frontmatter value as a list: nil -> {}, "x" -> {"x"}, {...} ->
-- {...}
-----------------------------------------------------------------------
function ITAM.list(value)
	if value == nil then return {} end
	if type(value) == "table" then return value end
	return { value }
end

-----------------------------------------------------------------------
-- ITAM.oneOf(value, values)
--
-- Whether `value` is one of `values`; an empty list accepts anything
-----------------------------------------------------------------------
function ITAM.oneOf(value, values)
	if #values == 0 then return true end
	for _, v in ipairs(values) do
		if v == value then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- ITAM.allOf(value, values)
--
-- Every value of a list (or the single value) is one of `values`
-----------------------------------------------------------------------
function ITAM.allOf(value, values)
	for _, v in ipairs(ITAM.list(value)) do
		if not ITAM.oneOf(v, values) then return false end
	end
	return true
end

-----------------------------------------------------------------------
-- ITAM.unlink(value)
--
-- "[[Some/Page]]" -> "Some/Page"
-----------------------------------------------------------------------
function ITAM.unlink(value)
	if type(value) ~= "string" then return nil end
	return string.match(value, "^%[%[(.-)%]%]$") or value
end

-----------------------------------------------------------------------
-- ITAM.link(name)
--
-- "Some/Page" -> "[[Some/Page]]"
-----------------------------------------------------------------------
function ITAM.link(name)
	return "[[" .. name .. "]]"
end

-----------------------------------------------------------------------
-- ITAM.short(name)
--
-- "Computer/Storage/volume1" -> "volume1"
-----------------------------------------------------------------------
function ITAM.short(name)
	return string.match(name, "[^/]+$") or name
end

-----------------------------------------------------------------------
-- ITAM.hasTag(page, tagName)
--
-- Whether a page carries the tag.
-----------------------------------------------------------------------
function ITAM.hasTag(page, tagName)
	for _, t in ipairs(ITAM.list(page.tags)) do
		if t == tagName then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- ITAM.inScope(name)
--
-- Pages of this documentation: under one of the configured roots
-----------------------------------------------------------------------
function ITAM.inScope(name)
	for _, root in ipairs(ITAM.config().roots) do
		if string.sub(name, 1, #root) == root then return true end
	end
	return false
end

-----------------------------------------------------------------------
-- ITAM.pages(tagName)
--
-- The only two queries: all pages with a tag, and one page by its name
-----------------------------------------------------------------------
function ITAM.pages(tagName)
	return query[[from index.pages(tagName)]]
end

-----------------------------------------------------------------------
-- ITAM.page(name)
--
-- One page by its name; nil when it is not indexed.
-----------------------------------------------------------------------
function ITAM.page(name)
	local found = query[[from p = index.pages() where p.name == name]]
	return found[1]
end

-----------------------------------------------------------------------
-- ITAM.byName(tagName)
--
-- Pages with a tag, keyed by name
-----------------------------------------------------------------------
function ITAM.byName(tagName)
	local byName = {}
	for _, page in ipairs(ITAM.pages(tagName)) do byName[page.name] = page end
	return byName
end

-----------------------------------------------------------------------
-- ITAM.copies(job)
--
-- The copies a job makes, as { from, to } page names. A snapshot keeps
-- its copy on the same storage, whatever else is listed as target.
-----------------------------------------------------------------------
function ITAM.copies(job)
	local copies = {}
	local definition = ITAM.definitionOf("job", job.type)
	if not definition.copy then return copies end
	for _, source in ipairs(ITAM.list(job.source)) do
		local targets = definition.inPlace and { source } or ITAM.list(job.target)
		for _, target in ipairs(targets) do
			table.insert(copies, { from = ITAM.unlink(source), to = ITAM.unlink(target) })
		end
	end
	return copies
end

-----------------------------------------------------------------------
-- ITAM.flowchart()
--
-- A Mermaid flowchart, built box by box: every box opens its page; a
-- box can sit in a named group (drawn as a subgraph). Groups come
-- first, then loose boxes, then edges.
-----------------------------------------------------------------------
function ITAM.flowchart()
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
		table.insert(into, { kind = "node", id = name, label = label or ITAM.short(name), shape = shape })
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
					kind = "subgraph", id = "group_" .. group, label = ITAM.short(group),
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
-- `lastReviewed`) and the `status` field of the kind, as configured.
-- The values of `type`, `auth`, `status`, `location` and `area` come
-- from the configuration, so the schema holds them as text and
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
-- object(kind, required, properties)
--
-- An object schema: its own fields, the fields every object may carry,
-- the `status` field as configured for the kind (none, required or
-- optional; an enum when the values are known), what is required
-----------------------------------------------------------------------
local function object(kind, required, properties)
	properties.decision     = links               -- governing decision(s)
	properties.lastReviewed = text                -- YYYY-MM-DD
	local status = ITAM.statusOf(kind)
	if status then
		if status.optional then
			properties.status = nullableConfigured(status.values)
		else
			properties.status = configured(status.values)
			table.insert(required, "status")
		end
	end
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
	local allowed = ITAM.typesOf(kind)
	if not ITAM.allOf(value, allowed) then
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
	local sites = ITAM.config().sites
	if value ~= nil and not ITAM.oneOf(value, sites) then
		return "location must be one of " .. table.concat(sites, ", ")
	end
end

-----------------------------------------------------------------------
-- checkStatus(kind, value)
--
-- "status must be one of …", "A <kind> needs a status", or nil when
-- `value` is allowed for `kind` in this space (any value for a kind
-- without `status`: the field is then free, like any other unknown
-- key).
-----------------------------------------------------------------------
local function checkStatus(kind, value)
	local status = ITAM.statusOf(kind)
	if not status then return nil end
	if value == nil then
		if not status.optional then return "A " .. kind .. " needs a status" end
		return nil
	end
	if not ITAM.oneOf(value, status.values) then
		return "status must be one of " .. table.concat(status.values, ", ")
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
	schema = object("host", { "type", "network" }, {
		type     = configured(ITAM.typesOf("host")),
		role     = text,
		location = nullableConfigured(ITAM.config().sites), -- every host except external
		network  = links,
		platform = text,                            -- OS and hardware
		lanIp    = schema.nullableArray("string"),  -- fixed or reserved addresses
	}),
	validate = function(o)
		local bad = checkType("host", o.type) or checkStatus("host", o.status) or checkSite(o.location)
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
	schema = object("service", { "type", "partOf", "purpose", "auth" }, {
		type       = oneOrMore(ITAM.typesOf("service")), -- a list when it runs differently per host
		partOf     = linkOrLinks,                   -- the host, or a list of hosts
		purpose    = text,
		provider   = text,                          -- for type external
		hostname   = text,                          -- e.g. notes.example.org
		lanIp      = schema.nullableArray("string"),-- macvlan containers
		auth       = configured(ITAM.typesOf("auth")),
		network    = links,
		exposedVia = links,                         -- the reverse proxy
		authVia    = links,                         -- the login service
		dependsOn  = links,
	}),
	validate = function(o)
		local bad = checkType("service", o.type) or checkStatus("service", o.status)
		if bad then return bad end
		if not ITAM.oneOf(o.auth, ITAM.typesOf("auth")) then
			return "auth must be one of " .. table.concat(ITAM.typesOf("auth"), ", ")
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
	schema = object("network", { "type" }, {
		type     = configured(ITAM.typesOf("network")),
		partOf   = link,                            -- the host, for Docker networks
		cidr     = text,
		location = nullableConfigured(ITAM.config().sites), -- for type lan
	}),
	validate = function(o)
		return checkType("network", o.type) or checkStatus("network", o.status) or checkSite(o.location)
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
	schema = object("storage", { "type" }, {
		type       = configured(ITAM.typesOf("storage")),
		partOf     = linkOrLinks,                   -- the host, or a list for a replica
		on         = links,                         -- the layer(s) below, one per host for a replica
		policies   = links,
		capacity   = text,
		redundancy = text,                          -- raid1, raid5, single
		encrypted  = flag,
		filesystem = text,
		path       = text,
		location   = nullableConfigured(ITAM.config().sites), -- where loose storage is kept
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
	}),
	validate = function(o)
		local bad = checkType("storage", o.type) or checkStatus("storage", o.status) or checkSite(o.location)
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
	schema = object("policy", { "type" }, {
		type               = configured(ITAM.typesOf("policy")),
		copies             = number,              -- the original included
		offsite            = flag,
		frequency          = text,
		retentionSnapshots = text,
		retentionLocal     = text,
		retentionOffsite   = text,
	}),
	validate = function(o)
		return checkType("policy", o.type) or checkStatus("policy", o.status)
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
	schema = object("job", { "type", "partOf", "schedule" }, {
		type       = configured(ITAM.typesOf("job")),
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
		local bad = checkType("job", o.type) or checkStatus("job", o.status)
		if bad then return bad end
		local definition = ITAM.definitionOf("job", o.type)
		if definition.copy and not o.source then
			return "A " .. o.type .. " job needs a source"
		end
		if definition.copy and not definition.inPlace and not o.target then
			return "A " .. o.type .. " job needs a target"
		end
	end,
	transform = icon("clock"),
}
