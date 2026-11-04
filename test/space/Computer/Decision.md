Index of the decisions of the test set-up.

${views.index("dr")}

## Graph

${views.decisions { statuses = { "accepted", "provisional", "proposed" }, relations = { "dependsOn", "related", "supersedes" } }}

## Attention

${views.drDueForReview()}

${views.drProvisional()}
