import type { SharedProps } from "@/types"
import type { AttachableRunbook } from "@/pages/incidents/components/index/attach-runbook-dialog"
import type { LinkableIncident } from "@/pages/incidents/components/index/link-incident-dialog"
import type { IncidentAction, IncidentDetail, TimelineEvent } from "@/types/serializers"

export type { IncidentDetail as Incident } from "@/types/serializers"
export type { IncidentAction } from "@/types/serializers"
export type { TimelineEvent } from "@/types/serializers"
export type TimelineChange = NonNullable<TimelineEvent["changes"]>[number]

// What the incident page receives beyond the shared props. Kept apart from
// SharedProps so a partial reload can be typed against exactly these keys.
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
}

export type IncidentPageProps = SharedProps & IncidentPageOwnProps
