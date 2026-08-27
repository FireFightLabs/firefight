import type { IncidentStatusSettings, LifecycleStage } from "@/types/serializers"

export interface LifecycleStageWithStatuses extends LifecycleStage {
  statuses: IncidentStatusSettings[]
}

export interface Severity {
  id: string
  name: string
  slug: string
  description: string
  color: string
  rank: number
  position: number
  isDefault: boolean
}

export interface WebhookDelivery {
  id: string
  eventType: string
  state: "completed" | "errored"
  responseCode: number | null
  errorMessage: string | null
  deliveredAt: string
}

export interface Webhook {
  id: string
  name: string
  url: string
  active: boolean
  subscribedEvents: string[]
  createdAt: string
  deliveries: WebhookDelivery[]
}

export interface ApiKey {
  id: string
  name: string
  tokenPrefix: string
  active: boolean
  permissions: Record<string, string[]>
  createdBy: string
  createdAt: string
  lastUsedAt: string | null
  expiresAt: string | null
}

export interface CatalogTypeOption {
  id: string
  name: string
  slug: string
  color?: string
  icon?: string
}

// Re-exported from the generated serializer types. Hand-writing these once
// let them drift: the list rendered a field that no longer existed.
export type {
  IncidentFieldDefinitionSettings,
  IncidentFormFieldSettings,
  IncidentFormSettings,
} from "@/types/serializers"

export interface IncidentConditionSettings {
  id: string
  conditionField: string
  operator: string
  values: string[]
  incidentFieldDefinitionId?: string | null
}

export interface ConfigurableOption {
  id: string
  name: string
  color?: string | null
  enabled: boolean
  isDefault?: boolean
  deletionBlockedReason?: string
  disableBlockedReason?: string
  defaultBlockedReason?: string
}
