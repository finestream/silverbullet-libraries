---
tags: meta/template/page
description: A host (a machine or device) of the ITAM library.
command: "ITAM: New Host"
suggestedName: "${ITAM.pagePrefix()}Host/"
confirmName: true
frontmatter: |
  tags:
  - component
  - host
  type:  # ${ITAM.hint("host")}
  role:  # what the host is for (not needed for type unused)
  location:  # ${ITAM.hint("sites")}; leave out for type external
  network:  # the networks it is on, as links
  platform:  # OS and hardware
  lanIp:  # fixed or reserved LAN addresses only; leave out for DHCP
  ${ITAM.statusLine("host")}
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
