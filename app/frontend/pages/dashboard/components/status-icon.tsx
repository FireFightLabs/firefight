import {
  IconCheck,
  IconCircleDashedCheck,
  IconLoader,
  IconUrgent,
} from "@tabler/icons-react"

import { LIFECYCLE_STAGES } from "@/lib/constants"

interface StatusIconProps {
  statusName: string
  lifecycleStage: string
}

export function StatusIcon({ statusName, lifecycleStage }: StatusIconProps) {
  if (lifecycleStage === LIFECYCLE_STAGES.CLOSED) {
    return <IconCheck className="size-4" stroke={2.5} />
  }

  switch (statusName) {
    case "Triage":
      return <IconUrgent className="size-3.5" />
    case "Monitoring":
      return <IconCircleDashedCheck className="size-3.5" />
    default:
      return <IconLoader className="size-3.5" />
  }
}
