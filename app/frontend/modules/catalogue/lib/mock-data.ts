import type { CatalogType, CatalogEntry } from "@/modules/catalogue/types"

export const mockTypes: CatalogType[] = [
  {
    id: "type-1",
    name: "Service",
    slug: "service",
    icon: "server",
    description: "Backend services, APIs, and infrastructure components that your teams own and operate",
    color: "#3B82F6",
    entryCount: 6,
    attributeDefinitions: [
      { id: "a1", key: "description", name: "Description", type: "text", required: false },
      { id: "a2", key: "owner", name: "Owner", type: "reference", required: true, referenceTypeId: "type-2" },
      { id: "a3", key: "tier", name: "Tier", type: "select", required: true, options: ["Critical", "Standard", "Internal"] },
      { id: "a4", key: "repository", name: "Repository", type: "text", required: false },
      { id: "a5", key: "slack_channel", name: "Slack Channel", type: "text", required: false },
      { id: "a6", key: "on_call_team", name: "On-Call Team", type: "reference", required: false, referenceTypeId: "type-2" },
    ],
  },
  {
    id: "type-2",
    name: "Team",
    slug: "team",
    icon: "users",
    description: "Engineering teams and squads responsible for services and on-call rotations",
    color: "#8B5CF6",
    entryCount: 4,
    attributeDefinitions: [
      { id: "b1", key: "description", name: "Description", type: "text", required: false },
      { id: "b2", key: "slack_channel", name: "Slack Channel", type: "text", required: false },
      { id: "b3", key: "manager", name: "Manager", type: "text", required: false },
      { id: "b4", key: "members", name: "Members", type: "list", required: false },
    ],
  },
  {
    id: "type-3",
    name: "Functionality",
    slug: "functionality",
    icon: "puzzle",
    description: "Product features and capabilities that customers interact with, mapped to underlying services",
    color: "#10B981",
    entryCount: 4,
    attributeDefinitions: [
      { id: "c1", key: "description", name: "Description", type: "text", required: false },
      { id: "c2", key: "services", name: "Services", type: "reference", required: false, referenceTypeId: "type-1" },
      { id: "c3", key: "owner", name: "Owner", type: "reference", required: true, referenceTypeId: "type-2" },
    ],
  },
]

export const mockEntries: CatalogEntry[] = [
  // Services — attributes keyed by stable key, references store entry IDs
  { id: "e1", typeId: "type-1", name: "payment-service", attributes: { description: "Handles all payment processing via Stripe and PayPal", owner: "e8", tier: "Critical", repository: "firefight/payment-service", slack_channel: "#eng-payments", on_call_team: "e8" }, createdAt: "2026-01-15T10:00:00Z", updatedAt: "2026-03-20T14:30:00Z" },
  { id: "e2", typeId: "type-1", name: "auth-service", attributes: { description: "Authentication and authorization via SAML, OAuth, and API keys", owner: "e7", tier: "Critical", repository: "firefight/auth-service", slack_channel: "#eng-platform", on_call_team: "e7" }, createdAt: "2026-01-15T10:00:00Z", updatedAt: "2026-03-18T09:15:00Z" },
  { id: "e3", typeId: "type-1", name: "api-gateway", attributes: { description: "Edge proxy for rate limiting, routing, and request transformation", owner: "e7", tier: "Critical", repository: "firefight/api-gateway", slack_channel: "#eng-platform", on_call_team: "e10" }, createdAt: "2026-02-01T08:00:00Z", updatedAt: "2026-03-22T11:45:00Z" },
  { id: "e4", typeId: "type-1", name: "notification-service", attributes: { description: "Email, SMS, and push notification delivery", owner: "e9", tier: "Standard", repository: "firefight/notifications", slack_channel: "#eng-growth", on_call_team: "e9" }, createdAt: "2026-02-10T14:00:00Z", updatedAt: "2026-03-15T16:20:00Z" },
  { id: "e5", typeId: "type-1", name: "search-service", attributes: { description: "Full-text search powered by Elasticsearch", owner: "e7", tier: "Standard", repository: "firefight/search", slack_channel: "#eng-platform", on_call_team: "e7" }, createdAt: "2026-02-15T09:00:00Z", updatedAt: "2026-03-10T10:00:00Z" },
  { id: "e6", typeId: "type-1", name: "analytics-pipeline", attributes: { description: "Event ingestion and data pipeline for business analytics", owner: "e10", tier: "Internal", repository: "firefight/analytics", slack_channel: "#eng-infra", on_call_team: "e10" }, createdAt: "2026-03-01T12:00:00Z", updatedAt: "2026-03-25T08:00:00Z" },

  // Teams
  { id: "e7", typeId: "type-2", name: "Platform", attributes: { description: "Core platform services, auth, and developer experience", slack_channel: "#team-platform", manager: "Sarah Chen", members: ["Sarah Chen", "James Wilson", "Alex Kim"] }, createdAt: "2026-01-10T09:00:00Z", updatedAt: "2026-03-20T10:00:00Z" },
  { id: "e8", typeId: "type-2", name: "Payments", attributes: { description: "Payment processing, billing, and revenue operations", slack_channel: "#team-payments", manager: "Maria Garcia", members: ["Maria Garcia", "Jordan Park", "Li Wei"] }, createdAt: "2026-01-10T09:00:00Z", updatedAt: "2026-03-18T10:00:00Z" },
  { id: "e9", typeId: "type-2", name: "Growth", attributes: { description: "User acquisition, notifications, and engagement features", slack_channel: "#team-growth", manager: "Emily Nguyen", members: ["Emily Nguyen", "David Kim"] }, createdAt: "2026-01-10T09:00:00Z", updatedAt: "2026-03-15T10:00:00Z" },
  { id: "e10", typeId: "type-2", name: "Infrastructure", attributes: { description: "Cloud infrastructure, CI/CD, and observability", slack_channel: "#team-infra", manager: "Tom Anderson", members: ["Tom Anderson", "Priya Patel", "Chris Lee"] }, createdAt: "2026-01-10T09:00:00Z", updatedAt: "2026-03-22T10:00:00Z" },

  // Functionalities — references store entry IDs
  { id: "e11", typeId: "type-3", name: "Checkout", attributes: { description: "End-to-end checkout flow including cart, payment, and confirmation", services: "e1", owner: "e8" }, createdAt: "2026-02-01T10:00:00Z", updatedAt: "2026-03-20T10:00:00Z" },
  { id: "e12", typeId: "type-3", name: "Authentication", attributes: { description: "Login, signup, SSO, and session management", services: "e2", owner: "e7" }, createdAt: "2026-02-01T10:00:00Z", updatedAt: "2026-03-18T10:00:00Z" },
  { id: "e13", typeId: "type-3", name: "Search", attributes: { description: "Product and content search with filters and ranking", services: "e5", owner: "e7" }, createdAt: "2026-02-15T10:00:00Z", updatedAt: "2026-03-10T10:00:00Z" },
  { id: "e14", typeId: "type-3", name: "Reporting", attributes: { description: "Business dashboards, analytics, and data exports", services: "e6", owner: "e10" }, createdAt: "2026-03-01T10:00:00Z", updatedAt: "2026-03-25T10:00:00Z" },
]

export function getEntriesByType(typeId: string): CatalogEntry[] {
  return mockEntries.filter((e) => e.typeId === typeId)
}

export function getEntryById(id: string): CatalogEntry | undefined {
  return mockEntries.find((e) => e.id === id)
}

export function getTypeBySlug(slug: string): CatalogType | undefined {
  return mockTypes.find((t) => t.slug === slug)
}

export function getTypeById(id: string): CatalogType | undefined {
  return mockTypes.find((t) => t.id === id)
}

export function resolveReference(entryId: string): string {
  const entry = getEntryById(entryId)
  return entry?.name ?? entryId
}
