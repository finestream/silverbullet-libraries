Index of the decisions of the test set-up.

${ITAM.views.index("dr")}

## Graph

${ITAM.views.decisions { statuses = { "accepted", "provisional", "proposed" }, relations = { "dependsOn", "related", "supersedes" } }}

## Per area

### infrastructure

${ITAM.views.decisions { area = "infrastructure" }}

### knowledge

${ITAM.views.decisions { area = "knowledge" }}

## Attention

${ITAM.views.drDueForReview()}

${ITAM.views.drProvisional()}
