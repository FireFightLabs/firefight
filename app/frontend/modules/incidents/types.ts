export interface IncidentStatus {
  name: string
  lifecycleStage: string
  color: string
}

export interface IncidentSeverity {
  name: string
  rank: number
  color: string
}

export interface IncidentType {
  name: string
}

export interface IncidentLead {
  name: string
  initials: string
}

export interface IncidentActor {
  name: string
}

export interface Incident {
  id: string
  identifier: string
  name: string
  summary: string
  status: IncidentStatus
  severity: IncidentSeverity
  type: IncidentType | null
  lead: IncidentLead | null
  declaredBy: IncidentActor | null
  declaredAt: string
  detectedAt: string | null
  resolvedAt: string | null
  source: string
  channelName: string | null
  isPrivate: boolean
}

export interface IncidentListItem {
  id: string
  identifier: string
  name: string
  severity: Pick<IncidentSeverity, "name" | "rank">
  status: Pick<IncidentStatus, "name" | "lifecycleStage">
  lead: string | null
  declaredAt: string
  resolvedAt: string | null
}

export interface IncidentAction {
  id: string
  description: string
  actionType: "action" | "followup"
  status: "open" | "in_progress" | "done"
  assignee: string | null
  createdBy: string
}

export interface TimelineEvent {
  id: string
  eventType: string
  actor: string
  createdAt: string
  description: string
  changes?: { field: string; before: string; after: string }[]
  details?: string
}
