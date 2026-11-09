---
tags: dr
id: 5
status: draft
area: infrastructure
date: "2026-02-01"
deciders: "@me"
owner: "@me"
lastReviewed: "2026-02-01"
supersedes:
dependsOn:
related:
---
# Name every disk

## Context
A decision with a status that only the configuration of this space knows
(`draft`, added as a name in `dr.statuses`): valid, shown with 📐, neither
active nor provisional.

## Decision
Every physical disk gets a page, also before it is in use.

${ITAM.views.page(_CTX.currentPage.name)}
