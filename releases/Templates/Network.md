---
tags: meta/template/page
description: A network (a LAN, a VPN, the internet, a Docker network) of the IT Asset Management library.
command: "ITAM: New Network"
suggestedName: "${ITAM.pagePrefix()}Network/"
confirmName: true
frontmatter: |
  tags:
  - component
  - network
  type:  # ${ITAM.hint("network")}
  partOf:  # the host, for Docker networks
  cidr:  # e.g. 192.168.1.0/24
  location:  # for type lan: ${ITAM.hint("sites")}
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
