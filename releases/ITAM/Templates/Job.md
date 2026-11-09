---
tags: meta/template/page
description: A job (something that runs on a schedule or at boot) of the ITAM library.
command: "ITAM: New Job"
suggestedName: "${ITAM.pagePrefix()}Job/"
confirmName: true
frontmatter: |
  tags:
  - component
  - job
  type:  # ${ITAM.hint("job")}
  partOf:  # the host it runs on
  tool:  # e.g. timemachine, rsync
  schedule:  # e.g. daily 01:02, every 4 hours, boot
  source:  # copy jobs: the storage copied from
  target:  # backup and sync jobs: the storage copied to
  implements:  # the policy it fulfils
  ${ITAM.statusLine("job")}
  lastReviewed: "${date.today()}"
---
|^|

${"$"}{ITAM.views.page(_CTX.currentPage.name)}
