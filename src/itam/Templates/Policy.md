---
tags: meta/template/page
description: A policy (a rule that storage must meet) of the IT Asset Management library.
command: "ITAM: New Policy"
suggestedName: "${ITAM.pagePrefix()}Policy/"
confirmName: true
frontmatter: |
  tags:
  - component
  - policy
  type:  # ${ITAM.hint("policy")}
  copies:  # the original included
  offsite:  # true or false
  frequency:  # e.g. daily, every 4 hours
  retentionLocal:
  retentionOffsite:
  retentionSnapshots:
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
