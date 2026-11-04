---
tags: meta/template/page
description: A policy (a rule that storage must meet) of the IT Asset Management library.
command: "Policy: New"
suggestedName: "${itam.pagePrefix()}Policy/"
confirmName: true
frontmatter: |
  tags:
  - component
  - policy
  type:  # ${itam.hint("policy")}
  copies:  # the original included
  offsite:  # true or false
  frequency:  # e.g. daily, every 4 hours
  retentionLocal:
  retentionOffsite:
  retentionSnapshots:
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{views.page(_CTX.currentPage.name)}
