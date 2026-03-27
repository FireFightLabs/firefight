import { Deferred, Head, Link, usePage } from "@inertiajs/react"
import {
  IconArrowLeft,
  IconDotsVertical,
  IconFlame,
  IconSparkles,
} from "@tabler/icons-react"

import type { Postmortem, PostmortemUpdate } from "@/types/serializers"
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
import { Skeleton } from "@/components/ui/skeleton"
import { incidentPath } from "@/lib/routes"

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

const updateTypeLabels: Record<string, string> = {
  generated: "Generated",
  edited: "Edited",
  ai_edited: "AI rewritten",
}

interface PostmortemPageProps {
  incident: { id: string; identifier: string; name: string }
  postmortem: Postmortem | null
  updates?: PostmortemUpdate[]
}

function UpdatesSkeleton() {
  return (
    <div className="space-y-2">
      {Array.from({ length: 3 }).map((_, i) => (
        <Skeleton key={i} className="h-4 w-48" />
      ))}
    </div>
  )
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
          <PostmortemEditor content={postmortem.htmlContent ?? undefined} />

          <Deferred data="updates" fallback={<UpdatesSkeleton />}>
            {(updates ?? []).length > 0 && (
              <div className="mt-12 border-t pt-6">
                <h3 className="text-sm font-medium text-muted-foreground mb-3">History</h3>
                <div className="space-y-2">
                  {(updates ?? []).map((update) => (
                    <div key={update.id} className="flex items-center gap-2 text-sm text-muted-foreground">
                      <span className="font-medium text-foreground">{update.editedBy}</span>
                      <span>{updateTypeLabels[update.updateType] ?? update.updateType}</span>
                      {update.changedSections.length > 0 && (
                        <span>({update.changedSections.join(", ")})</span>
                      )}
                      <span className="ml-auto tabular-nums">
                        {new Date(update.createdAt).toLocaleDateString("en-US", {
                          month: "short", day: "numeric", hour: "2-digit", minute: "2-digit"
                        })}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </Deferred>
        </main>
      </div>
    </>
  )
}
