import { IconExternalLink } from "@tabler/icons-react"

import { cn } from "@/lib/utils"

// An alert's title, linking to the alert's own page in the tool that sent it when the tool gave one.
export function AlertTitle({ title, sourceUrl, className }: { title: string; sourceUrl?: string | null; className?: string }) {
  if (!sourceUrl) {
    return <span className={cn("block truncate", className)}>{title}</span>
  }

  return (
    <a
      href={sourceUrl}
      target="_blank"
      rel="noreferrer"
      className={cn("flex min-w-0 items-center gap-1 rounded-sm transition-colors duration-150 hover:text-fg-secondary", className)}
    >
      <span className="truncate">{title}</span>
      <IconExternalLink className="size-3 shrink-0 text-fg-muted" aria-hidden />
    </a>
  )
}
