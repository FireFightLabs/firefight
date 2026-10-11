import { usePage } from "@inertiajs/react"

import { ScreenshotGrid } from "@/pages/agent/components/screenshot-grid"
import type { AgentPageProps } from "@/pages/agent/types"

interface ScreenshotCardProps {
  toolCallKey: string
}

// The pages a browser check saw, found by the tool call that took them.
export function ScreenshotCard({ toolCallKey }: ScreenshotCardProps) {
  const { screenshots } = usePage<AgentPageProps>().props
  const shown = (screenshots ?? []).filter((screenshot) => screenshot.toolCallId === toolCallKey)
  if (shown.length === 0) {
    return null
  }

  return <ScreenshotGrid screenshots={shown} />
}
