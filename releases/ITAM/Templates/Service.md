---
tags: meta/template/page
description: A service (something that runs and offers a function) of the ITAM library.
command: "ITAM: New Service"
suggestedName: "${ITAM.pagePrefix()}Service/"
confirmName: true
frontmatter: |
  tags:
  - component
  - service
  type:  # ${ITAM.hint("service")}; a list when it runs differently per host
  partOf:  # the host page(s); the same software on several hosts is one service
  purpose:
  hostname:  # e.g. notes.example.org
  auth:  # ${ITAM.hint("auth")}
  network:
  exposedVia:  # the reverse proxy, as a link
  authVia:  # the login service, as a link
  dependsOn:
  policies:  # the policies it must meet, e.g. how it is updated
  ${ITAM.statusLine("service")}
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
