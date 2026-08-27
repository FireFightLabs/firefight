import { useState } from "react"
import { IconFlask, IconSend } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import {
  actionLabel,
  runRoutingTest,
  sendRoutingTest,
  type SendTestResult,
  type TestResult,
} from "@/pages/settings/lib/alerts"
import { newRow, rowListOps, withRowIds, type RowListItem } from "@/pages/settings/lib/row-list"
import { FormErrors } from "@/pages/settings/components/form-errors"
import { AddRowButton, RemoveRowButton } from "@/pages/settings/components/row-list-buttons"

interface TesterField extends RowListItem {
  key: string
  value: string
}

function matchedRuleNumber(result: TestResult): number | null {
  const index = result.trace.findIndex((entry) => entry.matched)
  return index === -1 ? null : index + 1
}

export function CustomTestDialog({
  disabled,
  alertSourceId,
  canSend,
}: {
  disabled: boolean
  alertSourceId: string | null
  // Sending posts to Slack, so only a viewer who may change routing gets it.
  // Running the dry run stays open to everyone.
  canSend: boolean
}) {
  const [open, setOpen] = useState(false)
  const [fields, setFields] = useState<TesterField[]>(() =>
    withRowIds([
      { key: "service", value: "" },
      { key: "title", value: "" },
    ])
  )
  const [result, setResult] = useState<TestResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [testing, setTesting] = useState(false)
  const [sending, setSending] = useState(false)
  const [sendResult, setSendResult] = useState<SendTestResult | null>(null)

  const fieldRows = rowListOps<TesterField>(fields, (rows) => {
    setSendResult(null)
    setFields(rows)
  })

  function handleOpenChange(next: boolean) {
    setOpen(next)
    if (next) {
      setResult(null)
      setError(null)
      setSendResult(null)
    }
  }

  function fieldsPayload(): Record<string, string> {
    return Object.fromEntries(fields.filter((field) => field.key.trim()).map((field) => [field.key.trim(), field.value]))
  }

  async function runTest() {
    setTesting(true)
    setSendResult(null)
    try {
      const outcome = await runRoutingTest(fieldsPayload(), alertSourceId)
      setResult(outcome.result)
      setError(outcome.error)
    } finally {
      setTesting(false)
    }
  }

  async function sendTest() {
    setSending(true)
    try {
      setSendResult(await sendRoutingTest(fieldsPayload(), alertSourceId))
    } finally {
      setSending(false)
    }
  }

  const ruleNumber = result ? matchedRuleNumber(result) : null
  const showSend = canSend && Boolean(result?.matched && result.resolution?.notify)

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" disabled={disabled} title={disabled ? "Add a routing rule first" : undefined}>
          <IconFlask className="size-4" />
          Test custom alert
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Test a custom alert</DialogTitle>
          <DialogDescription>
            Enter the fields a real alert would carry. Pure evaluation: nothing is created, and the result
            shows which rule wins.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-2">
          {fields.map((field, index) => (
            <div key={field.rowId} className="flex items-center gap-2">
              <Input
                value={field.key}
                onChange={(event) => fieldRows.update(index, { key: event.target.value })}
                placeholder="field"
                className="w-36"
              />
              <Input
                value={field.value}
                onChange={(event) => fieldRows.update(index, { value: event.target.value })}
                placeholder="value"
                className="flex-1"
              />
              <RemoveRowButton label="Remove field" onClick={() => fieldRows.remove(index)} />
            </div>
          ))}
          <div className="flex items-center justify-between">
            <AddRowButton label="Add field" onClick={() => fieldRows.append(newRow({ key: "", value: "" }))} />
            <Button size="sm" onClick={runTest} disabled={testing}>
              <IconFlask className="size-4" />
              Run test
            </Button>
          </div>
        </div>

        <FormErrors errors={error} />

        {result && (
          <div className="flex flex-col gap-1.5 rounded-md border border-border bg-card p-3 text-xs">
            <div className="flex items-center gap-2">
              <Badge variant={result.matched ? "default" : "secondary"}>
                {result.matched ? (ruleNumber ? `Matched rule ${ruleNumber}` : "Matched") : "No match"}
              </Badge>
              {result.matched && result.outcome?.action && (
                <span className="text-muted-foreground">
                  → {actionLabel(result.outcome.action)}
                </span>
              )}
            </div>
            {result.resolution && (
              <div className="flex flex-col gap-0.5 text-muted-foreground">
                {result.resolution.invite.length > 0 && (
                  <span>would invite: <span className="text-foreground">{result.resolution.invite.join(", ")}</span></span>
                )}
                {result.resolution.notify && (
                  <span>would notify: <span className="text-foreground">{result.resolution.notify}</span></span>
                )}
                {result.resolution.notes.map((note, index) => (
                  <span key={index} className="text-amber-500/80">⚠ {note}</span>
                ))}
              </div>
            )}
            {showSend && (
              <div className="mt-1 flex items-center gap-2 border-t border-border pt-2">
                <Button size="sm" variant="outline" onClick={sendTest} disabled={sending || Boolean(sendResult?.sent)}>
                  <IconSend className="size-4" />
                  {sendResult?.sent ? "Sent" : "Send test message"}
                </Button>
                {sendResult?.sent && (
                  <span className="text-muted-foreground">
                    delivered to <span className="text-foreground">{sendResult.notify}</span>
                  </span>
                )}
                {sendResult?.error && <span className="text-destructive">{sendResult.error}</span>}
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
