import { CUSTOM_MCP_PROVIDER_KEY, INTEGRATION_KINDS, LIFECYCLE_STAGES } from "@/lib/generated/constants"

export { CUSTOM_MCP_PROVIDER_KEY, INTEGRATION_KINDS, LIFECYCLE_STAGES }

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
