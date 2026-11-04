---
tags:
- component
- service
type: container
partOf: "[[Computer/Host/nas]]"
purpose: single sign-on
hostname: login.example.org
auth: own
exposedVia:
- "[[Computer/Service/proxy]]"
dependsOn:
- "[[Computer/Service/proxy]]"
status: active
lastReviewed: "2026-01-15"
---
# login

${views.page(_CTX.currentPage.name)}
