import type { Pagination, SharedProps } from "@/types"
import type { InvestigationDetail, InvestigationListItem } from "@/types/serializers"

export interface InvestigationsPageProps extends SharedProps {
  [key: string]: unknown
  investigations: InvestigationListItem[]
  pagination: Pagination
  incident: IncidentFilter | null
}

// The one incident the list is narrowed to, when its header has several runs to show.
export interface IncidentFilter {
  id: string
  identifier: string
  name: string
}

export interface InvestigationPageProps extends SharedProps {
  [key: string]: unknown
  investigation: InvestigationDetail
}
