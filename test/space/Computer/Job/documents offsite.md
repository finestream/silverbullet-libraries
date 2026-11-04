---
tags:
- component
- job
type: backup
partOf: "[[Computer/Host/nas]]"
tool: cloud sync
schedule: daily 03:00
source:
- "[[Computer/Storage/documents]]"
target:
- "[[Computer/Storage/offsite bucket]]"
implements:
- "[[Computer/Policy/offsite]]"
encrypted: true
lastReviewed: "2026-01-15"
---
# documents offsite

${views.page(_CTX.currentPage.name)}
