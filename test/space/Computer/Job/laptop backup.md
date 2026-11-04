---
tags:
- component
- job
type: backup
partOf: "[[Computer/Host/laptop]]"
tool: rsync
schedule: daily 01:00
source:
- "[[Computer/Storage/laptop disk]]"
target:
- "[[Computer/Storage/documents]]"
implements:
- "[[Computer/Policy/offsite]]"
lastReviewed: "2026-01-15"
---
# laptop backup

${views.page(_CTX.currentPage.name)}
