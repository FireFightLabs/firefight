export type AttributeType = "text" | "number" | "boolean" | "select" | "reference" | "list"

export interface AttributeDefinition {
  id: string
  key: string
  name: string
  type: AttributeType
  required: boolean
  referenceTypeId?: string
  options?: string[]
}

export interface CatalogType {
  id: string
  name: string
  slug: string
  icon: string
  description: string
  color: string
  attributeDefinitions: AttributeDefinition[]
  entryCount: number
}

export interface CatalogEntry {
  id: string
  typeId: string
  name: string
  attributes: Record<string, unknown>
  createdAt: string
  updatedAt: string
}
