import { IconAlertTriangle, IconBrandGit, IconDotsVertical, IconFileText, IconRefresh, IconTrash } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { formatDateTime } from "@/lib/formatters"
import { HANDBOOK_SOURCE_KINDS } from "@/lib/generated/constants"
import type { HandbookSource } from "@/types/serializers"

interface SourceItemProps {
  source: HandbookSource
  canWrite: boolean
  onSync: (source: HandbookSource) => void
  onStop: (source: HandbookSource) => void
}

// Where synced pages come from, when it was last read and what went wrong, with Sync now and Stop syncing.
export function SourceItem({ source, canWrite, onSync, onStop }: SourceItemProps) {
  const Icon = source.kind === HANDBOOK_SOURCE_KINDS.REPOSITORY ? IconBrandGit : IconFileText

  function sync() {
    onSync(source)
  }

  function stop() {
    onStop(source)
  }

  return (
    <li className="flex items-start gap-2 rounded-md px-2 py-1.5">
      <Icon className="mt-0.5 size-4 shrink-0 text-fg-muted" />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="truncate text-sm text-fg-secondary">{source.label}</span>
        <span className="text-xs text-fg-muted">
          {source.connection ? `${source.connection}, ` : ""}
          {source.syncedAt ? `read ${formatDateTime(source.syncedAt)}` : "Reading…"}
        </span>
        {source.syncError && (
          <span className="flex items-start gap-1 text-xs text-warning">
            <IconAlertTriangle className="mt-px size-3.5 shrink-0" />
            <span className="line-clamp-3">{source.syncError}</span>
          </span>
        )}
      </div>
      {canWrite && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="size-7 shrink-0 text-muted-foreground">
              <IconDotsVertical className="size-4" />
              <span className="sr-only">More for {source.label}</span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-44">
            <DropdownMenuItem onClick={sync}>
              <IconRefresh className="size-4" />
              Sync now
            </DropdownMenuItem>
            <DropdownMenuItem variant="destructive" onClick={stop}>
              <IconTrash className="size-4" />
              Stop syncing
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </li>
  )
}
