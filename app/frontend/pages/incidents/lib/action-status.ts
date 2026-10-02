import { IconCircleCheck, IconClock, IconLoader } from "@tabler/icons-react"

export const actionStatusIcons: Record<string, typeof IconClock> = {
  open: IconClock,
  in_progress: IconLoader,
  done: IconCircleCheck,
}

export const actionStatusStyles: Record<string, string> = {
  open: "text-fg-muted",
  in_progress: "text-stage-active",
  done: "text-success",
}

export const actionStatusLabels: Record<string, string> = {
  open: "Open",
  in_progress: "In progress",
  done: "Done",
}
