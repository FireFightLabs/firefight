import * as React from "react"
import { Head, Link, useHttp, usePage } from "@inertiajs/react"
import {
  IconArrowLeft,
  IconCheck,
  IconDotsVertical,
  IconFlame,
  IconSparkles,
} from "@tabler/icons-react"

import type { Postmortem } from "@/types/serializers"
import { PostmortemEditor } from "@/modules/incidents/components/postmortem-editor"
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
import { incidentPath, incidentPostmortemPath } from "@/lib/routes"

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

interface PostmortemPageProps {
  incident: { id: string; identifier: string; name: string }
  postmortem: Postmortem | null
}

export default function PostmortemPage() {
  const { incident, postmortem, updates } = usePage<PostmortemPageProps>().props

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

  const saveTimerRef = React.useRef<ReturnType<typeof setTimeout>>()
  const { setData, patch, processing, recentlySuccessful } = useHttp({ html_content: "" })

  const handleContentUpdate = React.useCallback((html: string) => {
    clearTimeout(saveTimerRef.current)
    setData("html_content", html)
    saveTimerRef.current = setTimeout(() => {
      patch(incidentPostmortemPath(incident.id))
    }, 1500)
  }, [incident.id, setData, patch])

  React.useEffect(() => {
    return () => clearTimeout(saveTimerRef.current)
  }, [])

  return (
    <>
      <Head title={`Postmortem — ${incident.identifier}`} />
      <div className="min-h-screen bg-background">
        <header className="sticky top-0 z-50 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
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
              <Button variant="outline" size="sm">
                Review
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="size-8">
                    <IconDotsVertical className="size-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem>Export as PDF</DropdownMenuItem>
                  <DropdownMenuItem>Export as Markdown</DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem>
                    <IconSparkles className="size-4" />
                    AI Rewrite
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem>Mark as Completed</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-3xl px-4 py-12 lg:px-6">
          <PostmortemEditor content={postmortem.htmlContent ?? undefined} onUpdate={handleContentUpdate} />
        </main>
      </div>
    </>
  )
}
