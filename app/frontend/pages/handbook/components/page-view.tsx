import { IconAlertTriangle, IconDotsVertical, IconExternalLink, IconHistory, IconPencil, IconRefresh, IconSnowflake, IconTrash } from "@tabler/icons-react"
import { useMemo } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { MarkdownText } from "@/components/markdown-text"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { formatDate, formatDateTime } from "@/lib/formatters"
import { HANDBOOK_HALON_READS, HANDBOOK_PAGE_KINDS } from "@/lib/generated/constants"
import type { HandbookPage, HandbookSource } from "@/types/serializers"

interface PageViewProps {
  page: HandbookPage
  source: HandbookSource | null
  canWrite: boolean
  onEdit: () => void
  onHistory: () => void
  onDelete: () => void
  onSync: (source: HandbookSource) => void
}

// One page as people read it, with who wrote it and when and how Halon reads it. A synced page also says where it comes
// from and how its last sync went.
export function PageView({ page, source, canWrite, onEdit, onHistory, onDelete, onSync }: PageViewProps) {
  const headingIds = useMemo(() => Object.fromEntries(page.anchors.map(([ heading, anchor ]) => [ heading, anchor ])), [ page.anchors ])
  const directing = page.kind === HANDBOOK_PAGE_KINDS.DIRECTING
  const synced = page.kind === HANDBOOK_PAGE_KINDS.SYNCED

  function sync() {
    if (source) {
      onSync(source)
    }
  }

  return (
    <article className="flex flex-col gap-5">
      <header className="flex flex-col gap-3 border-b pb-4">
        <div className="flex items-start justify-between gap-3">
          <h2 className="text-xl font-semibold tracking-tight text-fg-headline [overflow-wrap:anywhere]">{page.title}</h2>
          <div className="flex shrink-0 items-center gap-1">
            {canWrite && !synced && (
              <Button type="button" size="sm" variant="outline" onClick={onEdit}>
                <IconPencil className="size-4" />
                Edit
              </Button>
            )}
            {page.history.length > 0 && (
              <Button type="button" size="sm" variant="ghost" onClick={onHistory}>
                <IconHistory className="size-4" />
                History
              </Button>
            )}
            {canWrite && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
                    <IconDotsVertical className="size-4" />
                    <span className="sr-only">More for {page.title}</span>
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-44">
                  {synced && source && (
                    <DropdownMenuItem onClick={sync}>
                      <IconRefresh className="size-4" />
                      Sync now
                    </DropdownMenuItem>
                  )}
                  <Blocked reason={page.deleteBlockedReason}>
                    <DropdownMenuItem variant="destructive" disabled={Boolean(page.deleteBlockedReason)} onClick={onDelete}>
                      <IconTrash className="size-4" />
                      Delete page
                    </DropdownMenuItem>
                  </Blocked>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5 text-xs text-muted-foreground">
          {page.halonReads === HANDBOOK_HALON_READS.WHOLE ? (
            <Badge variant="outline">Halon reads it whole</Badge>
          ) : (
            <Badge variant="outline">Halon searches it when needed</Badge>
          )}
          {synced ? (
            <span>
              Synced from {page.sourceLabel}
              {source?.syncedAt ? `, ${formatDateTime(source.syncedAt)}` : ", not read yet"}
            </span>
          ) : (
            page.updatedAt && (
              <span>
                {page.addedBy ? `${page.addedBy}, ` : ""}
                {formatDate(page.updatedAt)}
              </span>
            )
          )}
          {page.sourceUrl && (
            <a href={page.sourceUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-brand hover:underline">
              <IconExternalLink className="size-3.5" />
              Open the source
            </a>
          )}
        </div>
        {synced && source?.syncError && (
          <p className="flex items-start gap-2 rounded-md bg-warning-tint px-3 py-2 text-sm text-warning">
            <IconAlertTriangle className="mt-0.5 size-4 shrink-0" />
            <span>{source.syncError}</span>
          </p>
        )}
        {synced && <p className="text-xs text-muted-foreground">Change this page at its source. Firefight reads it again when the source changes, and every hour.</p>}
      </header>
      {directing && (
        <p className="text-sm">
          <span className="text-muted-foreground">Halon takes direction from</span> <span className="font-medium text-fg-primary">{page.directingRoleName ?? "the Incident Lead"}</span>
        </p>
      )}
      {page.roleSetAside && (
        <p className="text-sm text-warning">The role chosen here was disabled or deleted, so Halon follows the Incident Lead until someone chooses again.</p>
      )}
      {page.freezeWindows.length > 0 && (
        <section className="flex flex-col gap-2" aria-labelledby="handbook-page-freezes">
          <h3 id="handbook-page-freezes" className="text-xs font-medium text-muted-foreground">Freeze windows, which Halon's plans never run inside</h3>
          <ul className="flex flex-col gap-2">
            {page.freezeWindows.map((window, index) => (
              <li key={index} className="flex items-start gap-2.5 rounded-md border bg-surface-card px-3 py-2.5 text-sm text-fg-body">
                <IconSnowflake className="mt-0.5 size-4 shrink-0 text-brand" />
                <span className="min-w-0 flex-1 [overflow-wrap:anywhere]">{window.sentence}</span>
                {window.active && <Badge variant="outline" className="shrink-0 border-brand text-brand">Frozen now</Badge>}
              </li>
            ))}
          </ul>
        </section>
      )}
      {page.text ? (
        <MarkdownText text={page.text} headingIds={headingIds} className="text-[15px] text-fg-body! [&_:is(h1,h2,h3)]:mt-6 [&_h2]:text-base [&_h3]:text-[15px]" />
      ) : (
        !directing && page.freezeWindows.length === 0 && <p className="text-sm text-muted-foreground">This page is empty.</p>
      )}
    </article>
  )
}
