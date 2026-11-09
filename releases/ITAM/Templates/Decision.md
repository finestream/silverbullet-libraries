---
tags: meta/template/page
description: A decision record (tag dr) with the fields of the ITAM library.
command: "ITAM: New Decision"
suggestedName: "${ITAM.pagePrefix()}Decision/"
confirmName: true
frontmatter: |
  tags: dr
  id:  # the next free number
  ${ITAM.statusLine("dr")}
  area:  # one value or a list [a, b]: ${ITAM.hint("areas")}
  date: "${date.today()}"
  deciders: "${ITAM.drDefault("deciders")}"
  owner: "${ITAM.drDefault("owner")}"
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

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
