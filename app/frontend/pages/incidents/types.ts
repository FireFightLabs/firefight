import type { SharedProps } from "@/types"
import type { AttachableRunbook } from "@/pages/incidents/components/index/attach-runbook-dialog"
import type { LinkableIncident } from "@/pages/incidents/components/index/link-incident-dialog"
import type { IncidentAction, IncidentDetail, InvestigationDetail, TimelineEvent } from "@/types/serializers"

export type { IncidentDetail as Incident } from "@/types/serializers"
export type { IncidentAction } from "@/types/serializers"
export type { TimelineEvent } from "@/types/serializers"
export type TimelineChange = NonNullable<TimelineEvent["changes"]>[number]

// Kept apart from SharedProps so a partial reload can be typed against exactly
// these keys.
export interface IncidentPageOwnProps {
  incident: IncidentDetail
  timelineEvents?: TimelineEvent[]
  actions?: IncidentAction[]
  hasPostmortem: boolean
  postmortemStatus?: string
  postmortemGenerationState?: "generating" | "failed"
  attachableRunbooks: AttachableRunbook[]
  channelUrl?: string | null
  linkableIncidents: LinkableIncident[]
  memberChoices: { value: string; label: string }[]
  subscribed: boolean
  // The run the address asks for, drawn over the page.
  openInvestigation: InvestigationDetail | null
  // The Investigate button, absent where Halon is off or the person may not start a run.
  investigationStart: InvestigationStart | null
}

export interface InvestigationStart {
  // Why a run cannot start now, from the model. Null when it can.
  blockedReason: string | null
  // Opens the run already working on the incident over this page, which the disabled button points at.
  runningHref: string | null
}

export type IncidentPageProps = SharedProps & IncidentPageOwnProps
