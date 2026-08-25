import { IconCircleCheck, IconClock, IconLoader } from "@tabler/icons-react"

export const actionStatusIcons: Record<string, typeof IconClock> = {
  open: IconClock,
  in_progress: IconLoader,
  done: IconCircleCheck,
}

export const actionStatusStyles: Record<string, string> = {
  open: "text-muted-foreground",
  in_progress: "text-amber-400",
  done: "text-primary",
}

export const actionStatusLabels: Record<string, string> = {
  open: "Open",
  in_progress: "In progress",
  done: "Done",
}
