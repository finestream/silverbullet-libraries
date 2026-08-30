-----------------------------------------------------------------------
-- Package ImageGallery
--
-- Renders the images stored in a directory of the space as a paginated
-- grid of thumbnails.
-----------------------------------------------------------------------
ImageGallery = {}

-----------------------------------------------------------------------
-- ImageGallery.defaults
--
-- Fallback values for every gallery parameter. They are used for the
-- arguments the caller omitted and that the "imagegallery" section of
-- the CONFIG page does not set either.
-----------------------------------------------------------------------
ImageGallery.defaults = {
	directory = "",
	cols = 3,
	rows = 3,
	width = 200,
	height = 200
}

-----------------------------------------------------------------------
-- ImageGallery.imageExtensions
--
-- Extensions recognised as images for documents the server did not
-- report a content type for.
-----------------------------------------------------------------------
ImageGallery.imageExtensions = {
	avif = true,
	bmp = true,
	gif = true,
	ico = true,
	jpeg = true,
	jpg = true,
	png = true,
	svg = true,
	tif = true,
	tiff = true,
	webp = true
}

-----------------------------------------------------------------------
-- ImageGallery.viewSuffix
--
-- Suffix of the "imageGallery:" virtual page references.
--
-- It keeps a reference from ending in an image extension, which
-- SilverBullet would resolve to the document itself instead of the
-- virtual page.
-----------------------------------------------------------------------
ImageGallery.viewSuffix = ":view"

-----------------------------------------------------------------------
-- ImageGallery.state
--
-- Currently visible page of every rendered gallery, keyed by directory
-- and grid geometry.
--
-- SilverBullet re-renders widgets while the page is being edited.
-- Remembering the position here keeps such a re-render from throwing
-- the reader back to the first page of the gallery.
-----------------------------------------------------------------------
ImageGallery.state = {}

-----------------------------------------------------------------------
-- ImageGallery.config()
--
-- Reads the "imagegallery" section of the CONFIG page.
--
-- Returns:
--   Table with directory, cols, rows, width and height, where every
--   value the user did not configure is taken from
--   ImageGallery.defaults.
-----------------------------------------------------------------------
function ImageGallery.config()
	local effective = {}
	for key, value in pairs(ImageGallery.defaults) do
		effective[key] = value
	end
	for key, value in pairs(config.get("imagegallery", {})) do
		if value ~= nil and value ~= "" then
			effective[key] = value
		end
	end
	return effective
end

-----------------------------------------------------------------------
-- ImageGallery.dimension(value, fallback)
--
-- Coerces a gallery dimension (a column, row or pixel count) into a
-- positive integer.
--
-- Returns:
--   value as an integer, or fallback when value is nil, not a number
--   or smaller than 1.
-----------------------------------------------------------------------
function ImageGallery.dimension(value, fallback)
	local number = tonumber(value)
	if number == nil or number < 1 then
		number = tonumber(fallback) or 1
	end
	return math.floor(number)
end

-----------------------------------------------------------------------
-- ImageGallery.parsePair(value, firstFallback, secondFallback)
--
-- Parses a "<a>x<b>" pair as typed in the prompts of the insert
-- command, for example "4x3" or "320 x 240".
--
-- Returns:
--   The two numbers, each falling back to the supplied default when
--   the value cannot be parsed.
-----------------------------------------------------------------------
function ImageGallery.parsePair(value, firstFallback, secondFallback)
	local first, second = tostring(value or ""):match("^%s*(%d+)%s*[xX*]%s*(%d+)%s*$")
	return ImageGallery.dimension(first, firstFallback),
		ImageGallery.dimension(second, secondFallback)
end

-----------------------------------------------------------------------
-- ImageGallery.normalizeDirectory(directory)
--
-- Normalizes a directory argument: leading and trailing slashes are
-- removed, so that "", "/" and "/Images/" behave as expected.
--
-- Returns:
--   Space path without surrounding slashes, "" for the root of the
--   space.
--
-- The two substitutions are kept in separate statements on purpose:
-- gsub returns two values, and Space Lua cannot call a method on a
-- multi-value result, so chaining them raises "attempt to index a
-- userdata value".
-----------------------------------------------------------------------
function ImageGallery.normalizeDirectory(directory)
	directory = tostring(directory or "")
	directory = directory:gsub("^/+", "")
	directory = directory:gsub("/+$", "")
	return directory
end

-----------------------------------------------------------------------
-- ImageGallery.displayDirectory(directory)
--
-- Returns a normalized directory in a form suitable for display, the
-- root of the space being shown as "/".
-----------------------------------------------------------------------
function ImageGallery.displayDirectory(directory)
	if directory == "" then
		return "/"
	end
	return directory
end

-----------------------------------------------------------------------
-- ImageGallery.isImage(document)
--
-- Decides whether a document of the space is an image.
--
-- The content type reported by the server wins; documents without one
-- are classified by their extension (see
-- ImageGallery.imageExtensions).
-----------------------------------------------------------------------
function ImageGallery.isImage(document)
	local contentType = document.contentType
	if contentType ~= nil and contentType ~= "" then
		return contentType:startsWith("image/")
	end
	local extension = document.extension or document.name:match("%.([^.]+)$") or ""
	return ImageGallery.imageExtensions[extension:lower()] == true
end

-----------------------------------------------------------------------
-- ImageGallery.listImages(directory)
--
-- Lists the images stored in a directory of the space, sorted by name.
--
-- The listing is not recursive: images in sub directories belong to the
-- gallery of that sub directory.
--
-- Returns:
--   Array of document metadata tables (name, contentType, size, ...)
-----------------------------------------------------------------------
function ImageGallery.listImages(directory)
	local prefix = ""
	if directory ~= "" then
		prefix = directory .. "/"
	end
	local documents = space.listDocuments()
	local images = {}
	for _, document in ipairs(documents) do
		if document.name:startsWith(prefix) then
			local relative = document.name:sub(#prefix + 1)
			if not relative:find("/", 1, true) and ImageGallery.isImage(document) then
				table.insert(images, document)
			end
		end
	end
	table.sort(images, function(first, second)
		return first.name < second.name
	end)
	return images
end

-----------------------------------------------------------------------
-- ImageGallery.documentUrl(path)
--
-- Builds the URL a document of the space is served at.
--
-- The ".fs" endpoint and the escaping of colons match what the editor
-- itself uses to render image transclusions. The URL is relative to the
-- space root, which the client publishes as the document base URL.
-----------------------------------------------------------------------
function ImageGallery.documentUrl(path)
	return ".fs/" .. (path:gsub(":", "%%3A"))
end

-----------------------------------------------------------------------
-- ImageGallery.viewRef(path)
--
-- Reference of the virtual page showing a single image full size.
--
-- Returns:
--   "imageGallery:<path>:view", or nil when path contains a character
--   that cannot appear in a page reference, in which case callers
--   should link to the document itself.
-----------------------------------------------------------------------
function ImageGallery.viewRef(path)
	if path:find("[@#|<>%$]") then
		return nil
	end
	return "imageGallery:" .. path .. ImageGallery.viewSuffix
end

-----------------------------------------------------------------------
-- ImageGallery.thumbnail(document, width, height)
--
-- Builds one clickable thumbnail.
--
-- The image is scaled to fit inside the width x height bounding box
-- without being cropped or distorted, and is loaded lazily so that the
-- thumbnails of the gallery pages that are not on screen are only
-- fetched once they are shown.
--
-- Clicking navigates to the full size view of the image, or to the
-- document itself when its path cannot be expressed as a reference.
--
-- Returns:
--   DOM node
-----------------------------------------------------------------------
function ImageGallery.thumbnail(document, width, height)
	local target = ImageGallery.viewRef(document.name) or document.name
	local cell = dom.div {
		class = "image-gallery-thumbnail",
		title = document.name,
		style = string.format(
			"display:flex;align-items:center;justify-content:center;" ..
			"width:%dpx;height:%dpx;overflow:hidden;cursor:pointer;",
			width, height),
		onclick = function()
			editor.navigate(target)
		end
	}
	cell.appendChild(dom.img {
		src = ImageGallery.documentUrl(document.name),
		alt = document.name,
		loading = "lazy",
		style = string.format(
			"max-width:%dpx;max-height:%dpx;object-fit:contain;",
			width, height)
	})
	return cell
end

-----------------------------------------------------------------------
-- ImageGallery.imageGallery(directory, cols, rows, width, height)
--
-- Renders a paginated grid of thumbnails for the images of a
-- directory. This is the function the inserted Lua directive calls.
--
-- All arguments are optional; an omitted one is taken from the
-- "imagegallery" configuration and finally from ImageGallery.defaults:
--   directory - directory to list, "" for the root of the space
--   cols      - thumbnails per row
--   rows      - rows per gallery page
--   width     - width of the thumbnail bounding box, in pixels
--   height    - height of the thumbnail bounding box, in pixels
--
-- Pagination controls are only rendered when the directory holds more
-- than cols * rows images. The grid of a gallery page is built the
-- first time that page is shown.
--
-- Returns:
--   A block widget, or a message when the directory holds no image.
-----------------------------------------------------------------------
function ImageGallery.imageGallery(directory, cols, rows, width, height)
	local cfg = ImageGallery.config()
	directory = ImageGallery.normalizeDirectory(directory or cfg.directory)
	cols = ImageGallery.dimension(cols, cfg.cols)
	rows = ImageGallery.dimension(rows, cfg.rows)
	width = ImageGallery.dimension(width, cfg.width)
	height = ImageGallery.dimension(height, cfg.height)

	local images = ImageGallery.listImages(directory)
	if # images == 0 then
		return widget.markdownBlock("**ImageGallery**: no image found in `" ..
			ImageGallery.displayDirectory(directory) .. "`.")
	end

	local perPage = cols * rows
	local pageCount = math.ceil(# images / perPage)
	local key = string.format("%s|%d|%d", directory, cols, rows)

	-- Gallery page numbers double as keys of the grid table, so they are
	-- kept plain integers within 1..pageCount.
	local function clamp(number)
		return math.floor(math.min(math.max(tonumber(number) or 1, 1), pageCount))
	end

	local current = clamp(ImageGallery.state[key])

	local container = dom.div {
		class = "image-gallery",
		style = "display:flex;flex-direction:column;gap:0.5em;"
	}
	local gridHost = dom.div {
		style = "max-width:100%;overflow-x:auto;"
	}
	container.appendChild(gridHost)

	-- Grids of the gallery pages that have been shown so far, by page.
	local grids = {}
	-- Assigned below, but declared here so that showPage can use them.
	local label, previousButton, nextButton

	local function pageGrid(number)
		if grids[number] == nil then
			local grid = dom.div {
				class = "image-gallery-grid",
				style = string.format(
					"display:grid;grid-template-columns:repeat(%d,%dpx);" ..
					"gap:0.5em;justify-content:start;",
					cols, width)
			}
			local from = (number - 1) * perPage + 1
			local to = math.min(number * perPage, # images)
			for index = from, to do
				grid.appendChild(ImageGallery.thumbnail(images[index], width, height))
			end
			gridHost.appendChild(grid)
			grids[number] = grid
		end
		return grids[number]
	end

	local function showPage(number)
		current = clamp(number)
		ImageGallery.state[key] = current
		pageGrid(current)
		for index, grid in pairs(grids) do
			if index == current then
				grid.style.display = "grid"
			else
				grid.style.display = "none"
			end
		end
		if label ~= nil then
			label.textContent = string.format("Page %d of %d (%d images)",
				current, pageCount, # images)
			previousButton.disabled = current <= 1
			nextButton.disabled = current >= pageCount
		end
	end

	local function navigationButton(text, offset)
		return dom.button {
			type = "button",
			class = "image-gallery-nav",
			style = "cursor:pointer;",
			__rawText = text,
			onclick = function()
				showPage(current + offset)
			end
		}
	end

	if pageCount > 1 then
		label = dom.span { class = "image-gallery-page" }
		previousButton = navigationButton("‹ Previous", -1)
		nextButton = navigationButton("Next ›", 1)
		local navigation = dom.div {
			class = "image-gallery-navigation",
			style = "display:flex;align-items:center;gap:0.5em;"
		}
		navigation.appendChild(previousButton)
		navigation.appendChild(label)
		navigation.appendChild(nextButton)
		container.appendChild(navigation)
	end

	showPage(current)

	-- No "markdown" key here on purpose: SilverBullet 2.9 renders it
	-- *instead of* "html", which silently replaces the whole gallery with
	-- the text of its own directive.
	return widget.new {
		html = container,
		display = "block"
	}
end

-----------------------------------------------------------------------
-- ImageGallery.directive(directory, cols, rows, width, height)
--
-- Builds the Lua directive that renders a gallery, as inserted into the
-- page by the insert command and the slash command.
-----------------------------------------------------------------------
function ImageGallery.directive(directory, cols, rows, width, height)
	return string.format("${ImageGallery.imageGallery(%q, %d, %d, %d, %d)}",
		directory, cols, rows, width, height)
end

-----------------------------------------------------------------------
-- ImageGallery.promptGallery()
--
-- Asks for the directory and the geometry of a new gallery, the
-- prompts being pre-filled from the configuration.
--
-- Returns:
--   The Lua directive to insert, or nil when a prompt was cancelled.
-----------------------------------------------------------------------
function ImageGallery.promptGallery()
	local cfg = ImageGallery.config()

	local directory = editor.prompt("Image directory:", tostring(cfg.directory))
	if directory == nil then
		return nil
	end

	local grid = editor.prompt("Thumbnails per page (columns x rows):",
		string.format("%dx%d", ImageGallery.dimension(cfg.cols, 1),
			ImageGallery.dimension(cfg.rows, 1)))
	if grid == nil then
		return nil
	end
	local cols, rows = ImageGallery.parsePair(grid, cfg.cols, cfg.rows)

	local size = editor.prompt("Thumbnail size in pixels (width x height):",
		string.format("%dx%d", ImageGallery.dimension(cfg.width, 1),
			ImageGallery.dimension(cfg.height, 1)))
	if size == nil then
		return nil
	end
	local width, height = ImageGallery.parsePair(size, cfg.width, cfg.height)

	return ImageGallery.directive(
		ImageGallery.normalizeDirectory(directory), cols, rows, width, height)
end

-----------------------------------------------------------------------
-- ImageGallery.viewPage(reference)
--
-- Renders the virtual page of a single image.
--
-- Workflow:
--   1. Recover the document path from the page reference.
--   2. List the images of its directory to locate the image.
--   3. Show it full size, followed by links to the previous and the
--      next image of the directory and to the document itself.
--
-- Returns:
--   Markdown for the virtual page.
-----------------------------------------------------------------------
function ImageGallery.viewPage(reference)
	local path = reference:match("^(.+)" .. ImageGallery.viewSuffix .. "$")
	if path == nil then
		return "# Not an image\n\n`" .. reference ..
			"` is not an ImageGallery reference.\n"
	end

	local directory = path:match("^(.*)/[^/]*$") or ""
	local images = ImageGallery.listImages(directory)
	local position
	for index, document in ipairs(images) do
		if document.name == path then
			position = index
		end
	end
	if position == nil then
		return "# Image not found\n\nNo image `" .. path .. "` in this space.\n"
	end

	local navigation = {}
	if position > 1 then
		local previous = ImageGallery.viewRef(images[position - 1].name)
		if previous ~= nil then
			table.insert(navigation, "[[" .. previous .. "|‹ Previous]]")
		end
	end
	table.insert(navigation, string.format("%d of %d in `%s`",
		position, # images, ImageGallery.displayDirectory(directory)))
	if position < # images then
		local following = ImageGallery.viewRef(images[position + 1].name)
		if following ~= nil then
			table.insert(navigation, "[[" .. following .. "|Next ›]]")
		end
	end

	local page = {}
	table.insert(page, "# " .. (path:match("([^/]+)$") or path))
	table.insert(page, "")
	table.insert(page, "![[" .. path .. "]]")
	table.insert(page, "")
	table.insert(page, table.concat(navigation, " · "))
	table.insert(page, "")
	table.insert(page, "Document: [[" .. path .. "]]")
	return table.concat(page, "\n")
end

-----------------------------------------------------------------------
-- Insert an image gallery at the cursor.
-----------------------------------------------------------------------
command.define {
	name = "ImageGallery: Insert Gallery",
	run = function()
		local directive = ImageGallery.promptGallery()
		if directive == nil then
			return
		end
		editor.insertAtCursor(directive, false, false)
	end
}

-----------------------------------------------------------------------
-- slashcommand:imageGallery
--
-- Slash command inserting an image gallery in place.
--
-- Intended workflow:
--   /imageGallery
--   -> directory, columns x rows, width x height
--   -> the grid replaces the slash command
-----------------------------------------------------------------------
slashCommand.define {
	name = "imageGallery",
	run = function()
		local directive = ImageGallery.promptGallery()
		if directive == nil then
			return
		end
		editor.insertAtCursor(directive, false, false)
	end
}

-----------------------------------------------------------------------
-- Full size view of a single gallery image.
--
-- Pattern: imageGallery:<document path>:view
-----------------------------------------------------------------------
virtualPage.define {
	pattern = "imageGallery:(.+)",
	run = function(reference)
		return ImageGallery.viewPage(reference)
	end
}

-----------------------------------------------------------------------
-- imageGallery(directory, cols, rows, width, height)
--
-- Shorthand for ImageGallery.imageGallery, so that galleries can be
-- written as ${imageGallery("Images", 3, 3, 200, 200)}.
-----------------------------------------------------------------------
imageGallery = ImageGallery.imageGallery
