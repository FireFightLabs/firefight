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
