import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import type { WorkflowRun } from "@/types/serializers"
import { DECISION_LABELS, labelFor } from "@/components/investigations/labels"
import { formatWhen } from "@/pages/halon/components/workflows/labels"

// Every call the run's steps made and every notice they raised, as the activity log and the Monitoring page keep them.
export function RunCallsCard({ run }: { run: WorkflowRun }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Calls it made</CardTitle>
        <CardDescription className="mt-1">As the activity log keeps them. Reads of Firefight&apos;s own data are not kept there.</CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        {run.calls.length === 0 ? (
          <p className="px-6 pb-6 text-sm text-muted-foreground">It made no call the activity log keeps.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Call</TableHead>
                <TableHead>Decision</TableHead>
                <TableHead className="hidden sm:table-cell">Outcome</TableHead>
                <TableHead className="hidden md:table-cell">When</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {run.calls.map((call) => (
                <TableRow key={call.id}>
                  <TableCell className="text-sm">
                    <span className="font-mono text-xs">{call.actionKey}</span>
                    {call.connection && <span className="block text-xs text-muted-foreground">{call.connection}</span>}
                  </TableCell>
                  <TableCell className="text-sm">{labelFor(DECISION_LABELS, call.decision)}</TableCell>
                  <TableCell className="hidden sm:table-cell text-sm">
                    <span className="capitalize">{call.outcome ?? "-"}</span>
                    {call.summary && <span className="block text-xs text-muted-foreground">{call.summary}</span>}
                  </TableCell>
                  <TableCell className="hidden md:table-cell text-sm text-muted-foreground">{formatWhen(call.at)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
        {run.notices.length > 0 && (
          <div className="border-t px-6 py-4">
            <p className="mb-2 text-sm font-medium">Notices it raised</p>
            <ul className="flex flex-col gap-2 text-sm">
              {run.notices.map((notice) => (
                <li key={notice.id}>
                  <span className="font-medium">{notice.topic}</span>
                  <span className="text-muted-foreground">{notice.said ? " Said in a channel. " : " Waits to be said. "}</span>
                  <span className="text-fg-secondary">{notice.summary}</span>
                </li>
              ))}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
