---
tags: meta/template/page
description: Storage (anything that holds data, from a disk to a cloud account) of the IT Asset Management library.
command: "ITAM: New Storage"
suggestedName: "${ITAM.pagePrefix()}Storage/"
confirmName: true
frontmatter: |
  tags:
  - component
  - storage
  type:  # ${ITAM.hint("storage")}
  partOf:  # the host page(s); several for a replica kept in sync
  on:  # the layer(s) below, one per host for a replica
  policies:  # at least one; a "no backup" policy when nothing protects it
  path:
  capacity:  # for disks and volumes
  status: active  # active, spare, retired
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
