---
tags: meta/template/page
description: A decision record (tag dr) with the fields of the IT Asset Management library.
command: "Decision: New"
suggestedName: "${itam.pagePrefix()}Decision/"
confirmName: true
frontmatter: |
  tags: dr
  id:  # the next free number
  status: proposed
  area:  # ${itam.hint("areas")}
  date: "${date.today()}"
  deciders: "${itam.drDefault("deciders")}"
  owner: "${itam.drDefault("owner")}"
  lastReviewed: "${date.today()}"
  supersedes:
  dependsOn:
  related:
---
# ${"$"}{string.match(_CTX.currentPage.name, "[^/]+$")}

## Context
|^|

## Objective

## Decision

## Consequences

## Alternatives considered

## Open questions
<!-- Delete this section once no question is open. -->

${"$"}{views.page(_CTX.currentPage.name)}
