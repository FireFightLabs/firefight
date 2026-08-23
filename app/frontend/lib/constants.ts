export const LIFECYCLE_STAGES = {
  TRIAGE: "triage",
  ACTIVE: "active",
  CLOSED: "closed",
  CANCELED: "canceled",
} as const

export type LifecycleStageKey = (typeof LIFECYCLE_STAGES)[keyof typeof LIFECYCLE_STAGES]

export function statusVariant(lifecycleStage: string) {
  switch (lifecycleStage) {
    case LIFECYCLE_STAGES.ACTIVE:
      return "default" as const
    case LIFECYCLE_STAGES.CLOSED:
      return "secondary" as const
    default:
      return "outline" as const
  }
}

export const INTEGRATION_KINDS = {
  MCP: "mcp",
  HTTP: "http",
  NATIVE: "native",
} as const

// The nameless catalog entry that stands for any MCP server the admin
// points at. Mirrors Integration::PROVIDER_CUSTOM_MCP.
export const CUSTOM_MCP_PROVIDER_KEY = "custom_mcp"
