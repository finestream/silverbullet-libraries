---
tags: meta/template/page
description: A service (something that runs and offers a function) of the IT Asset Management library.
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
  status: active  # active, on-demand, parked (a service that is gone is deleted, not kept)
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
