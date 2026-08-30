Test page for the ImageGallery library. The images live in `Images/` of this
test space (eight solid colour PNGs of assorted aspect ratios, so that the
bounding box fit is visible).

## Paginated: 3 x 2 boxes of 200 x 150

Eight images in a six thumbnail page, so the navigation bar should appear.

${imageGallery("Images", 3, 2, 200, 150)}

## One page: 4 x 2 boxes of 120 x 120

Eight images in an eight thumbnail page, so there should be no navigation bar.

${imageGallery("Images", 4, 2, 120, 120)}

## Defaults from CONFIG

${imageGallery()}

## Empty directory

${imageGallery("Nowhere")}
