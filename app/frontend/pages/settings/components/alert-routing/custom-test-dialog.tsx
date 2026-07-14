import { useState } from "react"
import { IconFlask, IconPlus, IconSend, IconTrash } from "@tabler/icons-react"

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
import { ACTION_LABELS, type SendTestResult, type TestResult } from "@/pages/settings/lib/alerts"

interface TesterField {
  key: string
  value: string
}

export function CustomTestDialog({
  disabled,
  onRun,
  onSend,
}: {
  disabled: boolean
  onRun: (fields: Record<string, string>) => Promise<TestResult | null>
  onSend: (fields: Record<string, string>) => Promise<SendTestResult | null>
}) {
  const [open, setOpen] = useState(false)
  const [fields, setFields] = useState<TesterField[]>([
    { key: "service", value: "" },
    { key: "title", value: "" },
  ])
  const [result, setResult] = useState<TestResult | null>(null)
  const [testing, setTesting] = useState(false)
  const [sending, setSending] = useState(false)
  const [sendResult, setSendResult] = useState<SendTestResult | null>(null)

  function updateField(index: number, patch: Partial<TesterField>) {
    setFields((prev) => prev.map((f, i) => (i === index ? { ...f, ...patch } : f)))
  }

  function fieldsPayload(): Record<string, string> {
    return Object.fromEntries(fields.filter((f) => f.key.trim()).map((f) => [f.key.trim(), f.value]))
  }

  async function runTest() {
    setTesting(true)
    setSendResult(null)
    try {
      setResult(await onRun(fieldsPayload()))
    } finally {
      setTesting(false)
    }
  }

  async function sendTest() {
    setSending(true)
    try {
      setSendResult(await onSend(fieldsPayload()))
    } finally {
      setSending(false)
    }
  }

  const canSend = Boolean(result?.matched && result.resolution?.notify)

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" disabled={disabled}>
          <IconFlask className="size-4" />
          Test custom alert
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Test a custom alert</DialogTitle>
          <DialogDescription>
            Enter the fields a real alert would carry. Pure evaluation: nothing is created, and the rules
            table shows which rule wins.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-2">
          {fields.map((field, index) => (
            <div key={index} className="flex items-center gap-2">
              <Input
                value={field.key}
                onChange={(e) => updateField(index, { key: e.target.value })}
                placeholder="field"
                className="w-36"
              />
              <Input
                value={field.value}
                onChange={(e) => updateField(index, { value: e.target.value })}
                placeholder="value"
                className="flex-1"
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="size-8 text-muted-foreground"
                onClick={() => setFields((prev) => prev.filter((_, i) => i !== index))}
              >
                <IconTrash className="size-4" />
              </Button>
            </div>
          ))}
          <div className="flex items-center justify-between">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => setFields((prev) => [...prev, { key: "", value: "" }])}
            >
              <IconPlus className="size-4" />
              Add field
            </Button>
            <Button size="sm" onClick={runTest} disabled={testing}>
              <IconFlask className="size-4" />
              Run test
            </Button>
          </div>
        </div>

        {result && (
          <div className="flex flex-col gap-1.5 rounded-md border border-border bg-card p-3 text-xs">
            <div className="flex items-center gap-2">
              <Badge variant={result.matched ? "default" : "secondary"}>
                {result.matched ? "Matched" : "No match"}
              </Badge>
              {result.matched && result.outcome?.action && (
                <span className="text-muted-foreground">
                  → {ACTION_LABELS[result.outcome.action] ?? result.outcome.action}
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
                {result.resolution.notes.map((note, i) => (
                  <span key={i} className="text-amber-500/80">⚠ {note}</span>
                ))}
              </div>
            )}
            {canSend && (
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
