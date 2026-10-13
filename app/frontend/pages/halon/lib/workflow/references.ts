import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_REFERENCE_ROOTS } from "@/lib/generated/constants"
import type { WorkflowDocument, WorkflowStepNode } from "@/types/serializers"

// The steps that run before this one: those its connections come from, and theirs, and for a step inside a for each the
// steps before the for each too, since the loop starts once they finished.
export function stepsBefore(stepId: string | null, document: WorkflowDocument): WorkflowStepNode[] {
  if (!stepId) {
    return []
  }
  const byId = new Map(document.steps.map((step) => [ step.id, step ]))
  const found = new Set<string>()
  const visit = (id: string) => {
    for (const edge of document.edges) {
      if (edge.to === id && !found.has(edge.from)) {
        found.add(edge.from)
        visit(edge.from)
      }
    }
  }
  visit(stepId)
  const within = byId.get(stepId)?.within
  const outer = within ? stepsBefore(within, document) : []
  return [ ...outer, ...[ ...found ].flatMap((id) => byId.get(id) ?? []) ]
}

function reference(path: string): string {
  return `{{${path}}}`
}

// What a step can read, written as it reads it: the trigger's inputs, each earlier step's fields, and inside a for each
// the item and its place.
export function referencesFor(stepId: string | null, document: WorkflowDocument): SearchableSelectOption[] {
  const inputs = document.trigger.inputs.map((input) => ({
    value: reference(`${WORKFLOW_REFERENCE_ROOTS.INPUTS}.${input.key}`),
    label: `${input.key}, asked each time: ${input.question}`,
    group: "Inputs",
  }))
  const steps = stepsBefore(stepId, document).flatMap((step) => [
    { value: reference(`${WORKFLOW_REFERENCE_ROOTS.STEPS}.${step.name}`), label: `Everything ${step.title} handed on`, group: step.title },
    ...step.outputs.map((field) => ({
      value: reference(`${WORKFLOW_REFERENCE_ROOTS.STEPS}.${step.name}.${field}`),
      label: field.split("_").join(" "),
      group: step.title,
    })),
  ])
  const step = document.steps.find((each) => each.id === stepId)
  const loop = step?.within
    ? [
      { value: reference(WORKFLOW_REFERENCE_ROOTS.ITEM), label: "The item this time round", group: "For each" },
      { value: reference(WORKFLOW_REFERENCE_ROOTS.INDEX), label: "Its place in the list, from 0", group: "For each" },
    ]
    : []
  const trigger = { value: reference(WORKFLOW_REFERENCE_ROOTS.TRIGGER), label: "What started the run", group: "Trigger" }
  return [ ...inputs, trigger, ...loop, ...steps ]
}
