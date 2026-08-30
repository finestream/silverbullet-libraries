
# ImageGallery

Browse the images of your space from inside a page: `ImageGallery` renders the
images of a directory as a grid of thumbnails, paginates them when they do not
fit, and gives every image a permanent page of its own.

Everything is rendered from the documents already in your space. The library
stores nothing, caches nothing, and writes nothing but the one line of Lua that
renders the gallery.

## Features

* *Grids on demand* insert a gallery anywhere with `/imageGallery`: it asks for
  a directory, how many thumbnails per page and how large they should be, and
  leaves a single Lua directive behind that renders the grid in place.
* *Bounding boxes, not crops* every thumbnail is scaled to fit its
  `width` x `height` box, so portrait and landscape images live in the same grid
  without being cropped or stretched.
* *Pagination* when a directory holds more images than one page can show,
  previous/next controls appear below the grid. Paging happens in the browser,
  without touching your page, and the position survives the re-render that
  SilverBullet performs while you edit.
* *Lazy loading* only the thumbnails of the gallery page you are looking at are
  fetched, so pointing a gallery at a large directory stays cheap.
* *A page per image* clicking a thumbnail opens a virtual page showing that
  image full size, with links to the previous and the next image of the same
  directory.

## Suggested workflow

* Upload your images into a directory of your space (`Upload: File`, or simply
  drag and drop them into a page)
* Open the page where you want to see them
* Insert the gallery with `/imageGallery`
* Adjust the grid afterwards by editing the numbers in the inserted directive

## Configuration

Configuration is optional: without it, galleries default to a 3 x 3 grid of
200 x 200 pixel thumbnails. To change the defaults, add the following section to
your `CONFIG` page in a space-lua block:

```lua
config.set {
  imagegallery = {
      directory = "Images", --directory proposed by the insert command
      cols = 3, --thumbnails per row
      rows = 3, --rows per gallery page
      width = 200, --width of the thumbnail bounding box, in pixels
      height = 200, --height of the thumbnail bounding box, in pixels
  }
}
```

These values are only defaults: the arguments of an inserted gallery always win.

## Usage

### the gallery directive

A gallery is a Lua directive calling `imageGallery(directory, cols, rows, width,
height)`:

```
${imageGallery("Images", 4, 2, 160, 120)}
```

This shows the images of `Images` as 4 columns by 2 rows of thumbnails, each
fitting a 160 x 120 pixel box, with page navigation below the grid whenever the
directory holds more than 8 images. `ImageGallery.imageGallery(...)` is the same
function under its qualified name, which is what the insert command writes.

Every argument may be omitted, in which case the configured default is used:

```
${imageGallery("Images")}
${imageGallery()}
```

`directory` is a path in your space, without leading or trailing slashes;
`""` is the root of the space. The listing is not recursive: images in a sub
directory belong to the gallery of that sub directory.

### slashcommands

`/imageGallery` inserts a gallery in the current page

### commands

`ImageGallery: Insert Gallery` Inserts a gallery at the cursor

### virtual pages

`imageGallery:<path of the image>:view` Full size view of a single image, with
links to the previous and the next image of its directory

### styling

The gallery carries the CSS class `image-gallery`, the grid of one gallery page
`image-gallery-grid`, each thumbnail `image-gallery-thumbnail` and the
pagination bar `image-gallery-navigation`. Use them from a `space-style` block
to restyle a gallery, for example to give the thumbnails a frame:

```
.image-gallery-thumbnail {
  border: 1px solid var(--editor-widget-background-color);
  border-radius: 4px;
}
```

### notes

* A document counts as an image when the server reports an `image/` content
  type; documents without one are recognised by their extension (`png`, `jpg`,
  `jpeg`, `gif`, `webp`, `avif`, `bmp`, `svg`, `ico`, `tif`, `tiff`).
* Images whose path contains one of the characters `@ # | < > $` cannot be
  addressed by a page reference: their thumbnails link straight to the document
  instead of to the full size view.
* Rendering a gallery lists the documents of the space once, so a page holding
  many galleries costs one listing per gallery.
* Not tested with Silverbullet+

## Code
