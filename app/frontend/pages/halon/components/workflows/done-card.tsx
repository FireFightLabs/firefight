import { useState } from "react"
import { Link } from "@inertiajs/react"
import { IconRepeat } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { workflowPath } from "@/lib/routes"
import type { WorkflowRow, WorkflowRunRow } from "@/types/serializers"
import { RepeatDialog } from "@/pages/halon/components/workflows/repeat-dialog"
import { RunsTable } from "@/pages/halon/components/workflows/runs-table"

// One offs whose time came, each with its runs, which stay readable, and a way to make it repeat.
export function DoneCard({ done, runs, canManage, timeZones }: { done: WorkflowRow[]; runs: WorkflowRunRow[]; canManage: boolean; timeZones: string[] }) {
  const [repeating, setRepeating] = useState<WorkflowRow | null>(null)

  function closeRepeat() {
    setRepeating(null)
  }

  if (done.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Done</CardTitle>
          <CardDescription className="mt-1">A workflow that runs once moves here after its run, with what it did.</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="rounded-xl border border-dashed border-border px-6 py-8 text-center text-sm text-muted-foreground">Nothing has run once yet.</p>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="flex flex-col gap-6">
      {done.map((workflow) => (
        <Card key={workflow.id}>
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-4">
              <div className="min-w-0">
                <CardTitle><Link href={workflowPath(workflow.id)} className="hover:underline">{workflow.name}</Link></CardTitle>
                <CardDescription className="mt-1">{workflow.triggerWords}</CardDescription>
              </div>
              {canManage && (
                <Button size="sm" variant="outline" onClick={() => setRepeating(workflow)}>
                  <IconRepeat className="size-4" />
                  Repeat it
                </Button>
              )}
            </div>
          </CardHeader>
          <CardContent className="p-0">
            <RunsTable runs={runs.filter((run) => run.workflowId === workflow.id)} showWorkflow={false} />
          </CardContent>
        </Card>
      ))}
      <RepeatDialog workflowId={repeating?.id ?? null} workflowName={repeating?.name ?? ""} onClose={closeRepeat} timeZones={timeZones} />
    </div>
  )
}
