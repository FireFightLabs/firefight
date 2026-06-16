export type AttributeType = "text" | "number" | "boolean" | "select" | "reference" | "list" | "slack_channel" | "workspace_member" | "workspace_members"

export interface AttributeDefinition {
  id: string
  key: string
  name: string
  attributeType: AttributeType
  required: boolean
  position: number
  referenceTypeId?: string
  options?: string[]
}

export interface CatalogType {
  id: string
  name: string
  slug: string
  kind: string
  icon?: string
  description?: string
  color?: string
  attributeDefinitions: AttributeDefinition[]
  entryCount: number
  position: number
  systemKey?: string
}

export interface CatalogEntry {
  id: string
  typeId: string
  name: string
  slug: string
  attributes: Record<string, unknown>
  createdAt: string
  updatedAt: string
  externalId?: string
  source?: string
}

export interface ReferenceEntry {
  id: string
  name: string
  typeId: string
}

export type { SlackMember } from "@/hooks/use-member-search"

export interface SlackChannel {
  id: string
  name: string
}

export interface WorkspaceMember {
  id: string
  name: string
  avatarUrl?: string
}
