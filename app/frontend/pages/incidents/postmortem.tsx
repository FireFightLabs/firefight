import { useCallback, useEffect, useRef, useState } from "react"
import { Head, Link, router, useHttp, usePage } from "@inertiajs/react"
import {
  IconArrowLeft,
  IconCheck,
  IconClock,
  IconDotsVertical,
  IconFlame,
} from "@tabler/icons-react"

import TurndownService from "turndown"

import type { SharedProps } from "@/types"
import type { Postmortem } from "@/types/serializers"
import { PostmortemEditor } from "@/pages/incidents/components/postmortem/postmortem-editor"
import { PostmortemGeneratingSkeleton } from "@/pages/incidents/components/postmortem/postmortem-generating-skeleton"
import { RevisionsSheet } from "@/pages/incidents/components/postmortem/revisions-sheet"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Separator } from "@/components/ui/separator"
import { incidentPath, incidentPostmortemPath, incidentPostmortemStatusPath } from "@/lib/routes"
import { requestJson } from "@/lib/http"

const statusLabels: Record<string, string> = {
  draft: "Draft",
  in_progress: "In progress",
  in_review: "In review",
  completed: "Completed",
}

const statusStyles: Record<string, string> = {
  draft: "bg-muted text-muted-foreground",
  in_progress: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  in_review: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  completed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
}

interface PostmortemPageProps extends SharedProps {
  incident: { id: string; identifier: string; name: string }
  postmortem: Postmortem | null
}

export default function PostmortemPage() {
  const { incident, postmortem } = usePage<PostmortemPageProps>().props

  // All hooks run unconditionally — the null-postmortem branch returns after.
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const { setData, patch, processing, recentlySuccessful } = useHttp({ html_content: "" })
  const [editorKey, setEditorKey] = useState(0)
  const [revisionsOpen, setRevisionsOpen] = useState(false)
  const editorContentRef = useRef(postmortem?.htmlContent ?? "")

  const handleContentUpdate = useCallback((html: string) => {
    editorContentRef.current = html
    clearTimeout(saveTimerRef.current)
    setData("html_content", html)
    saveTimerRef.current = setTimeout(() => {
      saveTimerRef.current = undefined
      patch(incidentPostmortemPath(incident.id))
    }, 1500)
  }, [incident.id, setData, patch])

  const handleRestore = useCallback((html: string) => {
    editorContentRef.current = html
    setEditorKey((k) => k + 1)
    setData("html_content", html)
    patch(incidentPostmortemPath(incident.id))
  }, [incident.id, setData, patch])

  const handleExportMarkdown = useCallback(() => {
    if (!postmortem) {
      return
    }
    const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" })
    const title = `# ${postmortem.title}\n\n> ${incident.identifier} — ${incident.name}\n\n`
    const markdown = title + turndown.turndown(editorContentRef.current || "")
    const blob = new Blob([markdown], { type: "text/markdown" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `${incident.identifier}-postmortem.md`
    a.click()
    URL.revokeObjectURL(url)
  }, [incident, postmortem])

  useEffect(() => {
    // Uses raw fetch with keepalive instead of Inertia's router.patch so the
    // request survives page unload / tab close. Inertia's router has no
    // keepalive equivalent — the request would be cancelled on navigation.
    const flushPendingSave = () => {
      if (!saveTimerRef.current) {
        return
      }
      clearTimeout(saveTimerRef.current)
      saveTimerRef.current = undefined

      void requestJson(incidentPostmortemPath(incident.id), {
        method: 'PATCH',
        body: { html_content: editorContentRef.current },
        keepalive: true,
      })
    }

    const removeListener = router.on('before', flushPendingSave)
    return () => {
      removeListener()
      flushPendingSave()
    }
  }, [incident.id])

  const isGenerating = postmortem?.status === "in_progress"
  useEffect(() => {
    if (!isGenerating) {
      return
    }
    const interval = setInterval(() => {
      router.reload({ only: ["postmortem"], preserveScroll: true })
    }, 3000)
    return () => clearInterval(interval)
  }, [isGenerating])

  const wasGeneratingRef = useRef(isGenerating)
  useEffect(() => {
    if (wasGeneratingRef.current && !isGenerating && postmortem?.htmlContent) {
      editorContentRef.current = postmortem.htmlContent
      setEditorKey((k) => k + 1)
    }
    wasGeneratingRef.current = isGenerating
  }, [isGenerating, postmortem?.htmlContent])

  if (!postmortem) {
    return (
      <>
        <Head title={`Postmortem — ${incident.identifier}`} />
        <div className="flex min-h-screen items-center justify-center">
          <div className="text-center text-muted-foreground">
            <p>No postmortem has been generated for this incident yet.</p>
            <Link href={incidentPath(incident.id)} className="mt-4 inline-block text-primary hover:underline">
              Back to incident
            </Link>
          </div>
        </div>
      </>
    )
  }

  if (isGenerating) {
    return (
      <>
        <Head title={`Postmortem — ${incident.identifier}`} />
        <div className="min-h-screen bg-background">
          <header className="sticky top-0 z-50 border-b bg-background print:hidden">
            <div className="mx-auto flex h-12 max-w-4xl items-center gap-3 px-4 lg:px-6">
              <Link href={incidentPath(incident.id)} className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
                <IconArrowLeft className="size-3.5" />
                Back to incident
              </Link>
            </div>
          </header>
          <PostmortemGeneratingSkeleton />
        </div>
      </>
    )
  }

  return (
    <>
      <Head title={`Postmortem — ${incident.identifier}`} />
      <div className="min-h-screen bg-background">
        <header className="sticky top-0 z-50 border-b bg-background print:hidden">
          <div className="mx-auto flex h-12 max-w-4xl items-center gap-3 px-4 lg:px-6">
            <Link href={incidentPath(incident.id)} className="text-muted-foreground hover:text-foreground">
              <IconArrowLeft className="size-4" />
            </Link>
            <Separator orientation="vertical" className="h-4" />
            <nav className="flex items-center gap-1.5 text-sm text-muted-foreground overflow-hidden">
              <IconFlame className="size-4 shrink-0 text-primary" />
              <span className="hidden sm:inline">Incidents</span>
              <span className="hidden sm:inline">›</span>
              <span className="font-medium hidden sm:inline">{incident.identifier}</span>
              <span className="hidden sm:inline">›</span>
              <span className="truncate font-medium text-foreground">
                Postmortem
              </span>
            </nav>
            <div className="ml-auto flex items-center gap-2">
              {recentlySuccessful && (
                <span className="flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400">
                  <IconCheck className="size-3" />
                  Saved
                </span>
              )}
              {processing && (
                <span className="text-xs text-muted-foreground">Saving...</span>
              )}
              <Badge
                variant="secondary"
                className={`text-xs ${statusStyles[postmortem.status]}`}
              >
                {statusLabels[postmortem.status]}
              </Badge>
              <Button variant="outline" size="sm" onClick={() => setRevisionsOpen(true)}>
                <IconClock className="size-4" />
                Revisions
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="size-8">
                    <IconDotsVertical className="size-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onClick={() => window.print()}>Export as PDF</DropdownMenuItem>
                  <DropdownMenuItem onClick={handleExportMarkdown}>Export as Markdown</DropdownMenuItem>
                  <DropdownMenuSeparator />
                  {postmortem.status !== "completed" ? (
                    <DropdownMenuItem onClick={() => router.patch(incidentPostmortemStatusPath(incident.id), { status: "completed" })}>
                      Mark as Completed
                    </DropdownMenuItem>
                  ) : (
                    <DropdownMenuItem onClick={() => router.patch(incidentPostmortemStatusPath(incident.id), { status: "draft" })}>
                      Reopen as Draft
                    </DropdownMenuItem>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-3xl px-4 py-12 lg:px-6 print:px-0 print:py-0 print:max-w-none">
          <div className="hidden print:block mb-8">
            <h1 className="text-2xl font-bold">{postmortem.title}</h1>
            <p className="text-sm text-muted-foreground mt-1">{incident.identifier}: {incident.name}</p>
          </div>
          <PostmortemEditor
            key={editorKey}
            content={editorContentRef.current || undefined}
            onUpdate={handleContentUpdate}
            incidentId={incident.id}
          />
        </main>
      </div>

      <RevisionsSheet
        incidentId={incident.id}
        currentHtml={editorContentRef.current}
        open={revisionsOpen}
        onOpenChange={setRevisionsOpen}
        onRestore={handleRestore}
      />
    </>
  )
}
