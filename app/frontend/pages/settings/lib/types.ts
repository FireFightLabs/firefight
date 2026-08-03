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
  signingSecret: string
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

export interface IncidentFieldDefinitionSettings {
  id: string
  key: string
  name: string
  description?: string
  fieldType: string
  optionSource: string
  position: number
  options: string[]
  catalogTypeId?: string
  catalogTypeName?: string
  usageCount: number
}

export interface IncidentConditionSettings {
  id: string
  conditionField: string
  operator: string
  values: string[]
}

export interface IncidentFormFieldSettings {
  id: string
  fieldSourceKind: string
  systemFieldKey?: string
  incidentFieldDefinitionId?: string
  name: string
  description?: string
  slug: string
  fieldType: string
  optionSource?: string
  position: number
  visibilityMode: string
  requiredMode: string
  lockedRequired: boolean
  lockedVisible: boolean
  options?: { id: string; name: string }[]
  catalogTypeId?: string
  catalogTypeName?: string
  conditions?: IncidentConditionSettings[]
}

export interface IncidentFormSettings {
  id: string
  slug: string
  name: string
  description?: string
  lifecycleEvent: string
  position: number
  fieldCount: number
  fields: IncidentFormFieldSettings[]
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
