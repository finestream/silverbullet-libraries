---
kbProjectId: 2 
---

This is a test file with a few tasks

* [ ] Task 1 on page 
* [ ] Task 2 on page

${query[[from index.tasks() where pageId == _CTX.currentPage.pageId and column != "Done" select templates.taskItem(_)]]}
