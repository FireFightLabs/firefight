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
