
-----------------------------------------------------------------------
-- Decision records
--
-- The `dr` tag: a decision record after the ADR pattern, with a status
-- lifecycle, an area, the people who decide and own it, and links to
-- the decisions it rests on, relates to or supersedes. The views draw
-- the decisions as a graph and list those due for review.
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- ITAM.drDots
--
-- The status dot, used as page decoration and in the graph
-----------------------------------------------------------------------
ITAM.drDots = {
	proposed = "🟡", provisional = "🔵", accepted = "🟢",
	superseded = "⚪", deprecated = "🟠", rejected = "🔴",
}
ITAM.drStatuses = { "proposed", "provisional", "accepted", "superseded", "deprecated", "rejected" }
ITAM.drActive = { proposed = true, provisional = true, accepted = true }

-----------------------------------------------------------------------
-- Tag dr
--
-- The configured areas become an enum and the configured tag page is
-- set when the library loads; `validate` checks the area again when a
-- page is indexed.
-----------------------------------------------------------------------
local drConfig = ITAM.config().dr
local drSpec = {
	name = "dr",
	schema = {
		type = "object",
		properties = {
			status = {
				type = "string",
				enum = ITAM.drStatuses,
				description = "Lifecycle state: proposed -> provisional -> accepted, then superseded or deprecated; rejected is a dead end."
			},
			date = {
				type = "string",
				description = "Date the decision was made (YYYY-MM-DD)."
			},
			id = {
				type = "number",
				description = "Number of the decision, assigned at creation and never reused."
			},
			deciders = {
				type = "string",
				description = "Who makes the call: an identity, e.g. @me."
			},
			owner = {
				type = "string",
				description = "Who maintains this decision: an identity."
			},
			lastReviewed = {
				type = "string",
				description = "Date this decision was last reviewed (YYYY-MM-DD); feeds the review view."
			},
			area = {
				type = "string",
				description = "Which part of the space the decision belongs to; the allowed values are configured (dr.areas under the `itam` key of CONFIG)."
			},
			supersedes = {
				anyOf = { schema.array("string"), schema.null() },
				description = "The decision(s) this one supersedes, as page links. The inverse is a backlink."
			},
			dependsOn = {
				anyOf = { schema.array("string"), schema.null() },
				description = "Decisions this one rests on, as page links. The inverse is a backlink."
			},
			related = {
				anyOf = { schema.array("string"), schema.null() },
				description = "Non-directional see-also decisions, as page links."
			},
		},
		required = { "status" },
	},
	validate = function(o)
		local areas = ITAM.config().dr.areas
		if o.area ~= nil and not ITAM.oneOf(o.area, areas) then
			return "area must be one of " .. table.concat(areas, ", ")
		end
	end,
	transform = function(o)
		o.pageDecoration = { prefix = (ITAM.drDots[o.status] or "📐") .. " " }
		return o
	end,
}
if #drConfig.areas > 0 then drSpec.schema.properties.area.enum = drConfig.areas end
if drConfig.tagPage then drSpec.tagPage = drConfig.tagPage end
tag.define(drSpec)

-----------------------------------------------------------------------
-- ITAM.views.decisions(opts)
--
-- Decision records as a graph: nodes carry the status dot and the id.
-- opts.area (optional) keeps one area; opts.statuses (optional list)
-- keeps those statuses; opts.relations (default { "dependsOn" }) says
-- which frontmatter links become edges; `related` is drawn without
-- arrow label, `supersedes` labelled. Links to decisions outside the
-- selection are not drawn. opts.direction (default "TD") is the
-- Mermaid direction.
-----------------------------------------------------------------------
function ITAM.views.decisions(opts)
	opts = opts or {}
	local relations = opts.relations or { "dependsOn" }
	local keep = nil
	if opts.statuses then
		keep = {}
		for _, s in ipairs(opts.statuses) do keep[s] = true end
	end
	local pages, selected = {}, {}
	for _, page in ipairs(ITAM.pages("dr")) do
		if (not opts.area or page.area == opts.area) and (not keep or keep[page.status]) then
			table.insert(pages, page)
			selected[page.name] = true
		end
	end
	table.sort(pages, function(a, b) return (a.id or 0) < (b.id or 0) end)

	local chart = ITAM.flowchart()
	for _, page in ipairs(pages) do
		local dot = ITAM.drDots[page.status] or "📐"
		local label = dot .. " " .. ITAM.short(page.name)
		if page.id then label = label .. " (" .. page.id .. ")" end
		chart.box(page.name, label, nil, "rounded")
	end
	for _, page in ipairs(pages) do
		for _, rel in ipairs(relations) do
			for _, value in ipairs(ITAM.list(page[rel])) do
				local target = ITAM.unlink(value)
				if selected[target] then
					chart.edge(page.name, target, (rel ~= "dependsOn") and rel or nil)
				end
			end
		end
	end
	if chart.size == 0 then return widget.markdownBlock("*No decisions.*") end
	return chart.render(opts.direction or "TD")
end

-----------------------------------------------------------------------
-- dayTime(text)
--
-- "2026-01-31" or "2026-01-31T10:00:00" -> the time at noon of that
-- day; nil otherwise
-----------------------------------------------------------------------
local function dayTime(text)
	if type(text) ~= "string" then return nil end
	local year, month, day = string.match(text, "^(%d%d%d%d)-(%d%d)-(%d%d)")
	if not year then return nil end
	return os.time { year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }
end

-----------------------------------------------------------------------
-- ITAM.views.drDueForReview(days)
--
-- The active decisions (proposed, provisional, accepted) whose
-- `lastReviewed` is missing or older than `days` (default: the
-- configured reviewDays), oldest first
-----------------------------------------------------------------------
function ITAM.views.drDueForReview(days)
	days = days or ITAM.config().dr.reviewDays
	local limit = os.time() - days * 86400
	local due = {}
	for _, page in ipairs(ITAM.pages("dr")) do
		local reviewed = dayTime(page.lastReviewed)
		if ITAM.drActive[page.status] and (reviewed == nil or reviewed < limit) then
			table.insert(due, page)
		end
	end
	table.sort(due, function(a, b)
		local ra, rb = a.lastReviewed or "", b.lastReviewed or ""
		if ra ~= rb then return ra < rb end
		return (a.id or 0) < (b.id or 0)
	end)
	return widget.markdownBlock(ITAM.views.section("Due for review (older than " .. days .. " days)",
		{ "decision", "id", "owner", "last reviewed" },
		ITAM.views.pageRows(due, { "id", "owner", "lastReviewed" })))
end

-----------------------------------------------------------------------
-- ITAM.views.drProvisional()
--
-- The provisional decisions with the days since their last change,
-- longest unchanged first
-----------------------------------------------------------------------
function ITAM.views.drProvisional()
	local rows, pages = {}, {}
	for _, page in ipairs(ITAM.pages("dr")) do
		if page.status == "provisional" then table.insert(pages, page) end
	end
	table.sort(pages, function(a, b) return (a.lastModified or "") < (b.lastModified or "") end)
	local now = os.time()
	for _, page in ipairs(pages) do
		local changed = dayTime(page.lastModified)
		local days = changed and math.floor((now - changed) / 86400) or ""
		table.insert(rows, { page.id, ITAM.link(page.name), days, page.lastReviewed })
	end
	return widget.markdownBlock(ITAM.views.section("Provisional",
		{ "id", "decision", "days since last change", "last reviewed" }, rows))
end
