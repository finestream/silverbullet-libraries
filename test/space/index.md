---
pageId: 011b9e85-0d83-4440-824f-cd46608361ef
---

This is a test file with a few tasks

* [ ] Task 1 
* [ ] Task 2 

${query[[from index.tasks() where pageId == "011b9e85-0d83-4440-824f-cd46608361ef" and column != "Done" select templates.taskItem(_)]]}

${query[[from index.tasks() where pageId == _CTX.currentPage.pageId and column != "Done" select templates.taskItem(_)]]}

