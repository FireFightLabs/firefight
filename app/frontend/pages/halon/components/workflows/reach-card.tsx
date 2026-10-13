import { IconCircleCheck, IconCircleDashed } from "@tabler/icons-react"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import type { WorkflowDetail } from "@/types/serializers"

// What the workflow's own identity needs to run its steps, and whether an admin granted each yet.
export function ReachCard({ workflow }: { workflow: WorkflowDetail }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>What it can do</CardTitle>
        <CardDescription className="mt-1">
          It runs as {workflow.agentName ?? "its own identity"}, never as whoever started it, and holds only what an admin granted. Publishing grants what its steps need.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {workflow.reach.length === 0 ? (
          <p className="text-sm text-muted-foreground">Its steps need nothing granted.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {workflow.reach.map((need) => (
              <li key={need.key} className="flex items-center gap-2 text-sm">
                {need.held ? <IconCircleCheck className="size-4 shrink-0 text-success" /> : <IconCircleDashed className="size-4 shrink-0 text-muted-foreground" />}
                <span>{need.label}</span>
                <span className="text-xs text-muted-foreground">{need.held ? "Granted" : "Needs a grant"}</span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
