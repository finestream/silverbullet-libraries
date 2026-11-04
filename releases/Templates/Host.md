---
tags: meta/template/page
description: A host (a machine or device) of the IT Asset Management library.
command: "Host: New"
suggestedName: "${itam.pagePrefix()}Host/"
confirmName: true
frontmatter: |
  tags:
  - component
  - host
  type:  # ${itam.hint("host")}
  role:  # what the host is for (not needed for type unused)
  location:  # ${itam.hint("sites")}; leave out for type external
  network:  # the networks it is on, as links
  platform:  # OS and hardware
  lanIp:  # fixed or reserved LAN addresses only; leave out for DHCP
  status: active  # active, on-demand, parked, free (a host that is gone is deleted, not kept)
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{views.page(_CTX.currentPage.name)}
