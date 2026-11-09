---
tags:
- component
- policy
type: backup
copies: 3
offsite: true
frequency: daily
retentionLocal: 30 days
retentionOffsite: 1 year
decision:
- "[[Computer/Decision/001 One copy offsite]]"
status: active
lastReviewed: "2026-01-15"
---
# offsite

${ITAM.views.page(_CTX.currentPage.name)}
