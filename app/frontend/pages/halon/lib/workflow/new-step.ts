import { WORKFLOW_CALL_TOOL } from "@/lib/generated/constants"
import { jsonObject, type JsonObject } from "@/lib/tool-fields"
import type { WorkflowDocument, WorkflowStepKind, WorkflowToolChoice } from "@/types/serializers"

const ID_LENGTH = 12
const ID_LETTERS = "abcdefghijklmnopqrstuvwxyz0123456789"
const NAME_LIMIT = 64

// What the palette hands the canvas when a step is dragged or clicked: a kind, or a tool for a Call a tool step.
export type PaletteChoice = { kind: WorkflowStepKind; tool: WorkflowToolChoice | null }

// The data a palette entry carries while it is dragged onto the canvas.
export const DRAG_TYPE = "application/x-firefight-workflow-step"

// A new step's id, which never changes, made here so the step can be connected the moment it is added.
export function newStepId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(ID_LENGTH))
  return `step_${Array.from(bytes, (byte) => ID_LETTERS[byte % ID_LETTERS.length]).join("")}`
}

// A name later steps can refer to it by, from its kind or tool, unique in the workflow: wait_for_event, then
// wait_for_event_2.
export function newStepName(base: string, document: WorkflowDocument): string {
  const taken = new Set(document.steps.map((step) => step.name))
  const cleaned = base.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").replace(/^(\d)/, "step_$1").slice(0, NAME_LIMIT - 3) || "step"
  if (!taken.has(cleaned)) {
    return cleaned
  }
  let count = 2
  while (taken.has(`${cleaned}_${count}`)) {
    count += 1
  }
  return `${cleaned}_${count}`
}

// The step an add_step edit sends: its id, name, kind, the config its kind starts with and where it was put, or no place
// when the canvas should lay it out.
export function newStep(choice: PaletteChoice, document: WorkflowDocument, position: { x: number; y: number } | null): JsonObject {
  const config: JsonObject = jsonObject(choice.kind.defaults)
  if (choice.tool) {
    config[WORKFLOW_CALL_TOOL.TOOL] = choice.tool.name
    config[WORKFLOW_CALL_TOOL.ARGUMENTS] = {}
  }
  const step: JsonObject = { id: newStepId(), name: newStepName(choice.tool?.name ?? choice.kind.label, document), kind: choice.kind.key, config }
  if (position) {
    step.position = { x: Math.round(position.x), y: Math.round(position.y) }
  }
  return step
}
