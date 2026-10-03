import {
  IconActivity,
  IconCheck,
  IconCircleOff,
  IconFocus2,
  IconLoader2,
  IconProgress,
  IconSearch,
  type Icon,
} from "@tabler/icons-react"

import { LIFECYCLE_STAGES, type LifecycleStageKey } from "@/lib/constants"
import { DEFAULT_STATUS_SLUGS } from "@/lib/generated/constants"

// The default statuses share a stage, so each gets its own mark. Any other status takes its stage's.
const STATUS_ICONS: Record<string, Icon> = {
  [DEFAULT_STATUS_SLUGS.TRIAGING]: IconLoader2,
  [DEFAULT_STATUS_SLUGS.INVESTIGATING]: IconSearch,
  [DEFAULT_STATUS_SLUGS.IDENTIFIED]: IconFocus2,
  [DEFAULT_STATUS_SLUGS.MONITORING]: IconActivity,
  [DEFAULT_STATUS_SLUGS.RESOLVED]: IconCheck,
  [DEFAULT_STATUS_SLUGS.CANCELED]: IconCircleOff,
}

const STAGE_ICONS: Record<LifecycleStageKey, Icon> = {
  [LIFECYCLE_STAGES.TRIAGE]: IconLoader2,
  [LIFECYCLE_STAGES.ACTIVE]: IconProgress,
  [LIFECYCLE_STAGES.CLOSED]: IconCheck,
  [LIFECYCLE_STAGES.CANCELED]: IconCircleOff,
}

interface StatusIconProps {
  statusSlug: string
  lifecycleStage: LifecycleStageKey
}

export function StatusIcon({ statusSlug, lifecycleStage }: StatusIconProps) {
  const StatusMark = STATUS_ICONS[statusSlug] ?? STAGE_ICONS[lifecycleStage]
  return <StatusMark className="size-3.5 shrink-0" stroke={2} aria-hidden="true" />
}
