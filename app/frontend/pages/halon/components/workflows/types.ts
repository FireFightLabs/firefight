import type { SharedProps } from "@/types"
import type { WorkflowPublishRequest, WorkflowRow, WorkflowRunRow } from "@/types/serializers"

export interface WorkflowTemplateChoice {
  key: string
  name: string
  description: string
}

export interface RunsPage {
  number: number
  more: boolean
}

export interface TeamChoice {
  id: string
  name: string
}

export interface PublishRequestStanding {
  waiting: boolean
  askBlockedReason?: string | null
}

export type WorkflowInput = WorkflowRow["inputs"][number]

export interface WorkflowsPageProps extends SharedProps {
  workflows: WorkflowRow[]
  done: WorkflowRow[]
  doneRuns: WorkflowRunRow[]
  runs: WorkflowRunRow[]
  runsPage: RunsPage
  templates: WorkflowTemplateChoice[]
  publishRequests: WorkflowPublishRequest[]
  timeZones: string[]
}

