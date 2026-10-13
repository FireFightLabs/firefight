import type { SharedProps } from "@/types"
import type { PublishRequestStanding, TeamChoice } from "@/pages/halon/components/workflows/types"
import type {
  RunbookPlace,
  RunbookWatchRead,
  WorkflowDetail,
  WorkflowDocument,
  WorkflowHalonChange,
  WorkflowPublishRequest,
  WorkflowRunDetail,
  WorkflowRunRow,
  WorkflowRunStates,
  WorkflowStepKind,
  WorkflowStepNode,
  WorkflowSuggestion,
  WorkflowToolChoice,
  WorkflowTriggerKind,
  WorkflowVersionRow,
} from "@/types/serializers"

export interface OtherWorkflow {
  name: string
  slug: string
}

// What the person may do on the canvas, as the gateway answers: build the draft, and manage the workflow (publish it,
// change its settings, switch it on or off and delete it).
export interface WorkflowAccess {
  build: boolean
  manage: boolean
}

export interface WorkflowPageProps extends SharedProps {
  workflow: WorkflowDetail
  document: WorkflowDocument
  versions: WorkflowVersionRow[]
  suggestions: WorkflowSuggestion[]
  halonChanges: WorkflowHalonChange[]
  stepKinds: WorkflowStepKind[]
  triggerKinds: WorkflowTriggerKind[]
  // Deferred, since listing every tool reads each connection's schemas.
  tools?: WorkflowToolChoice[]
  publishRequests: WorkflowPublishRequest[]
  otherWorkflows: OtherWorkflow[]
  timeZones: string[]
  teams: TeamChoice[]
  myPublishRequest: PublishRequestStanding
  workflowAccess: WorkflowAccess
  // Deferred, since listing what is on the map reads every connection.
  places?: RunbookPlace[]
  watchReads?: RunbookWatchRead[]
  runs: WorkflowRunRow[]
  // The run the address names, drawn on the canvas, or null while editing.
  run: WorkflowRunDetail | null
  // The newest run of the version shown, which Last run lays over the steps.
  lastRun: WorkflowRunStates | null
}

export type Edge = WorkflowDocument["edges"][number]

export type Trigger = WorkflowDocument["trigger"]

export type StepField = WorkflowStepKind["fields"][number]

// What the inspector shows: a step, the trigger, or nothing.
export type Selection = { kind: "step"; id: string } | { kind: "trigger" } | null

export const VIEWS = { EDITOR: "editor", RUNS: "runs", VERSIONS: "versions", SETTINGS: "settings" } as const
export type CanvasView = (typeof VIEWS)[keyof typeof VIEWS]

// How a step stood in a run, for its node: its state, how long it took, and whether it waits on an approval. A step
// inside a for each stands for every item it ran.
export interface StepRunState {
  status: WorkflowRunStates["steps"][number]["status"]
  // Words for its node's corner, such as 2.1s or 3 of 5.
  label: string
  waitingApproval: boolean
}

// A step as the canvas holds it, with what Halon suggests doing to it.
export interface CanvasStep {
  step: WorkflowStepNode
  // A step Halon suggests adding, drawn dashed until someone accepts it.
  suggestion: WorkflowSuggestion | null
  // Halon's suggestions to remove it, change it or rename it.
  pending: WorkflowSuggestion[]
  // How it stood in the run shown, or in the last run while Last run is on.
  state?: StepRunState
}
