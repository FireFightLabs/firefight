import { useEffect, useMemo, useState } from "react"
import { IconArrowLeft, IconClock } from "@tabler/icons-react"
import HtmlDiff from "htmldiff-js"

import type { PostmortemUpdate } from "@/types/serializers"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { withExternalLinksInNewTab } from "@/lib/links"
import { incidentPostmortemRevisionsPath } from "@/lib/routes"

export function RevisionsSheet({
  incidentId,
  currentHtml,
  open,
  onOpenChange,
  onRestore,
}: {
  incidentId: string
  currentHtml: string
  open: boolean
  onOpenChange: (open: boolean) => void
  onRestore: (html: string) => void
}) {
  const [revisions, setRevisions] = useState<PostmortemUpdate[]>([])
  const [loading, setLoading] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)

  useEffect(() => {
    if (!open) {
      return
    }

    const controller = new AbortController()
    setLoading(true)
    fetch(incidentPostmortemRevisionsPath(incidentId), { signal: controller.signal })
      .then((res) => res.json())
      .then((data) => {
        setRevisions(data)
        setLoading(false)
      })
      .catch((err) => {
        if (err.name !== "AbortError") {
          setLoading(false)
        }
      })

    return () => controller.abort()
  }, [open, incidentId])

  const selectedRevision = selectedId ? revisions.find((revision) => revision.id === selectedId) : null
  const selectedIndex = selectedRevision ? revisions.indexOf(selectedRevision) : -1

  const diffHtml = useMemo(() => {
    if (!selectedRevision?.htmlContent) {
      return null
    }
    const olderHtml = selectedRevision.htmlContent
    // Revisions are newest first, so the next version is the previous index or the live editor content.
    const newerHtml = selectedIndex === 0 ? currentHtml : (revisions[selectedIndex - 1]?.htmlContent ?? currentHtml)
    try {
      return withExternalLinksInNewTab(HtmlDiff.execute(olderHtml, newerHtml))
    } catch {
      return null
    }
  }, [selectedRevision, selectedIndex, revisions, currentHtml])

  const revisionHtml = useMemo(() => {
    if (!selectedRevision?.htmlContent) {
      return null
    }
    return withExternalLinksInNewTab(selectedRevision.htmlContent)
  }, [selectedRevision])

  function restoreSelected() {
    if (!selectedRevision?.htmlContent) {
      return
    }
    onRestore(selectedRevision.htmlContent)
    onOpenChange(false)
    setSelectedId(null)
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Revisions</SheetTitle>
          <SheetDescription>
            {selectedRevision ? "Viewing revision" : "Select a revision to preview"}
          </SheetDescription>
        </SheetHeader>
        <div className="flex min-w-0 flex-col gap-4 px-4 pb-6">
          {loading && (
            <div className="space-y-3">
              {Array.from({ length: 4 }).map((_, index) => (
                <Skeleton key={index} className="h-12 w-full" />
              ))}
            </div>
          )}

          {!loading && !selectedRevision && (
            <div className="space-y-1">
              {revisions.map((rev) => (
                <button
                  key={rev.id}
                  onClick={() => setSelectedId(rev.id)}
                  className="flex w-full items-center gap-3 rounded-lg border p-3 text-left transition-colors duration-120 hover:bg-surface-hover"
                >
                  <IconClock className="size-4 text-muted-foreground shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium">{rev.editedBy}</div>
                    <div className="text-xs text-muted-foreground">
                      {rev.label}
                    </div>
                  </div>
                  <span className="text-xs text-muted-foreground tabular-nums shrink-0">
                    {new Date(rev.createdAt).toLocaleDateString("en-US", {
                      month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
                    })}
                  </span>
                </button>
              ))}
              {revisions.length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-8">
                  No revisions yet.
                </p>
              )}
            </div>
          )}

          {selectedRevision && (
            <div className="flex flex-col gap-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Button variant="ghost" size="sm" onClick={() => setSelectedId(null)}>
                  <IconArrowLeft className="size-3" />
                  Back
                </Button>
                <Button size="sm" onClick={restoreSelected} disabled={!selectedRevision.htmlContent}>
                  Restore this version
                </Button>
              </div>
              <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted-foreground">
                <span className="font-medium text-fg-primary">{selectedRevision.editedBy}</span>
                <span>·</span>
                <span>{selectedRevision.label}</span>
                <span>·</span>
                <span>
                  {new Date(selectedRevision.createdAt).toLocaleDateString("en-US", {
                    month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
                  })}
                </span>
              </div>
              <Separator />
              {diffHtml ? (
                <div
                  className="prose prose-sm prose-invert max-w-none rounded-lg border bg-surface-code p-4 [&_ins]:rounded-sm [&_ins]:bg-success-tint [&_ins]:px-0.5 [&_ins]:text-success [&_ins]:no-underline [&_del]:rounded-sm [&_del]:bg-error-tint [&_del]:px-0.5 [&_del]:text-error [&_del]:line-through"
                  dangerouslySetInnerHTML={{ __html: diffHtml }}
                />
              ) : revisionHtml ? (
                <div
                  className="prose prose-sm prose-invert max-w-none rounded-lg border bg-surface-code p-4"
                  dangerouslySetInnerHTML={{ __html: revisionHtml }}
                />
              ) : (
                <p className="text-sm text-muted-foreground text-center py-8">
                  No content snapshot available for this revision.
                </p>
              )}
            </div>
          )}
        </div>
      </SheetContent>
    </Sheet>
  )
}
