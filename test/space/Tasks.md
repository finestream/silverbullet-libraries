The task table of the Kanboard library, `Kanboard.views.tasks`, over the made-up cache page [[Kanboard/900]]. Zürich ⭕️: this line holds characters of more than one byte on purpose.

# All tasks, default columns

${Kanboard.views.tasks(query[[from t = index.tasks() where t.projectId == 900 order by t.kbId]])}

# Open tasks in Ready, own columns

${Kanboard.views.tasks(query[[from t = index.tasks() where t.column == "Ready" and not t.done order by t.due]], {
  {"Due", "due", "DD.MM.YY"},
  {"Category", "category"},
  {"Tags", "tags"},
})}

# Tasks written on pages, no attribute columns

${Kanboard.views.tasks(query[[from t = index.tasks() where not t.kbId order by t.page]], {})}

# No task

${Kanboard.views.tasks(query[[from t = index.tasks() where t.column == "No such column"]])}

# Tasks written on this page

* [ ] A task written on this page
* [x] A done task written on this page

${Kanboard.views.tasks(query[[from t = index.tasks() where t.page == "Tasks"]], {})}

# Task link

The link of a task, `Kanboard.views.taskLink`: ${Kanboard.views.taskLink(757)} and as a string ${Kanboard.views.taskLink("757")}.

Not a task, each shows `(nothing)`: 0 ${Kanboard.views.taskLink(0) or "(nothing)"}, -3 ${Kanboard.views.taskLink(-3) or "(nothing)"}, 1.5 ${Kanboard.views.taskLink(1.5) or "(nothing)"}, "7 #x" ${Kanboard.views.taskLink("7 #x") or "(nothing)"}, 1e21 ${Kanboard.views.taskLink(1e21) or "(nothing)"}.
