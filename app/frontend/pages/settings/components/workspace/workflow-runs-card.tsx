import { useState, type FormEvent } from "react"
import type { Errors } from "@inertiajs/core"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_RUN_RETENTION_DAYS } from "@/lib/generated/constants"
import { settingsWorkspaceWorkflowsPath } from "@/lib/routes"

function messageOf(errors: Errors): string | undefined {
  const message = errors.workflow_run_retention_days
  return Array.isArray(message) ? message[0] : message
}

// How long a workflow run keeps what each step did. It saves on its own, since it lives apart from the page's form.
export function WorkflowRunsCard({ days }: { days: number }) {
  const [value, setValue] = useState(String(days))
  const [errors, setErrors] = useState<Errors>({})
  const [saving, setSaving] = useState(false)

  function cleared() {
    setErrors({})
  }

  function finish() {
    setSaving(false)
  }

  function save(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    router.patch(settingsWorkspaceWorkflowsPath(), { workflow_run_retention_days: value }, { preserveScroll: true, onSuccess: cleared, onError: setErrors, onFinish: finish })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Workflow runs</CardTitle>
        <CardDescription className="mt-1">
          How long a run keeps what each of its steps took in and gave back. After that it keeps one line for good: when it ran, what started it and how it ended. A pinned run keeps everything.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={save} className="max-w-prose">
          <Label htmlFor="workflow-run-retention" className="text-foreground">Keep run details for</Label>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Input
              id="workflow-run-retention"
              type="number"
              min={WORKFLOW_RUN_RETENTION_DAYS.MIN}
              max={WORKFLOW_RUN_RETENTION_DAYS.MAX}
              value={value}
              onChange={(event) => setValue(event.target.value)}
              className="w-28"
            />
            <span className="text-sm text-muted-foreground">days, from {WORKFLOW_RUN_RETENTION_DAYS.MIN} to {WORKFLOW_RUN_RETENTION_DAYS.MAX}</span>
            <Button type="submit" variant="outline" disabled={saving}>Save</Button>
          </div>
          {messageOf(errors) && <p className="mt-2 text-sm text-destructive">{messageOf(errors)}</p>}
        </form>
      </CardContent>
    </Card>
  )
}
