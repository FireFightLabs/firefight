import {
  IconCircleCheckFilled,
  IconCircleDashedCheck,
  IconLoader,
  IconUrgent,
} from "@tabler/icons-react"

export function getStatusIcon(statusName: string, lifecycleStage: string) {
  if (lifecycleStage === "closed") {
    return <IconCircleCheckFilled className="fill-green-500 dark:fill-green-400" />
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
