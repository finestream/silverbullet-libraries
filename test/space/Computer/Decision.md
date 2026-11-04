Index of the decisions of the test set-up.

${ITAM.views.index("dr")}

## Graph

${ITAM.views.decisions { statuses = { "accepted", "provisional", "proposed" }, relations = { "dependsOn", "related", "supersedes" } }}

## Attention

${ITAM.views.drDueForReview()}

${ITAM.views.drProvisional()}
