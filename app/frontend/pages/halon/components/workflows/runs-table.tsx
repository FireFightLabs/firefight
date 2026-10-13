import { Link, router } from "@inertiajs/react"
import { IconPin } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { workflowRunPath } from "@/lib/routes"
import type { WorkflowRunRow } from "@/types/serializers"
import { formatWhen, runStatusLabel, runTone } from "@/pages/halon/components/workflows/labels"
import { StatusPill } from "@/pages/halon/components/workflows/status-pill"
import type { RunsPage } from "@/pages/halon/components/workflows/types"

function goToPage(number: number) {
  router.get(window.location.pathname, { ...Object.fromEntries(new URLSearchParams(window.location.search)), page: number }, { preserveScroll: true, preserveState: true })
}

// Runs newest first, a page at a time, so every run stays reachable. showWorkflow names the workflow on a list of many.
export function RunsTable({ runs, page, showWorkflow }: { runs: WorkflowRunRow[]; page?: RunsPage; showWorkflow: boolean }) {
  return (
    <>
      <Table>
        <TableHeader>
          <TableRow>
            {showWorkflow && <TableHead>Workflow</TableHead>}
            <TableHead>Status</TableHead>
            <TableHead className="hidden md:table-cell">Started by</TableHead>
            <TableHead>Started</TableHead>
            <TableHead className="hidden sm:table-cell">Finished</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {runs.map((run) => (
            <TableRow key={run.id}>
              {showWorkflow && <TableCell className="font-medium">{run.workflowName}</TableCell>}
              <TableCell>
                <Link href={workflowRunPath(run.workflowId, run.id)} className="inline-flex items-center gap-2">
                  <StatusPill label={runStatusLabel(run.status)} tone={runTone(run.status)} />
                  {run.test && <span className="text-xs text-muted-foreground">Test</span>}
                  {run.pinned && <IconPin className="size-3.5 text-muted-foreground" aria-label="Pinned" />}
                </Link>
              </TableCell>
              <TableCell className="hidden md:table-cell text-sm text-muted-foreground">{run.startedByWords}</TableCell>
              <TableCell className="text-sm">
                <Link href={workflowRunPath(run.workflowId, run.id)} className="text-link hover:underline">{formatWhen(run.createdAt)}</Link>
              </TableCell>
              <TableCell className="hidden sm:table-cell text-sm text-muted-foreground">{run.finishedAt ? formatWhen(run.finishedAt) : "-"}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      {page && (page.number > 1 || page.more) && (
        <div className="flex items-center justify-between border-t px-4 py-3 text-sm text-muted-foreground">
          <span>Page {page.number}</span>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" disabled={page.number <= 1} onClick={() => goToPage(page.number - 1)}>Newer</Button>
            <Button size="sm" variant="outline" disabled={!page.more} onClick={() => goToPage(page.number + 1)}>Older</Button>
          </div>
        </div>
      )}
    </>
  )
}
