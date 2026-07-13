import { useState } from "react"
import { IconFlask, IconPlus, IconTrash } from "@tabler/icons-react"

import { alertRoutingTestPath } from "@/lib/routes"
import { ACTION_LABELS, csrfToken } from "@/pages/settings/lib/alerts"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"

interface TesterField {
  key: string
  value: string
}

interface TraceCondition {
  field: string
  operator: string
  actual: string | null
  matched: boolean
}

interface TraceEntry {
  rule_id: string
  priority: number
  matched: boolean
  conditions: TraceCondition[]
}

interface TestResult {
  matched: boolean
  outcome: { action?: string } | null
  trace: TraceEntry[]
}

export function RouteTester({ hasPolicy }: { hasPolicy: boolean }) {
  const [fields, setFields] = useState<TesterField[]>([
    { key: "service", value: "" },
    { key: "title", value: "" },
  ])
  const [result, setResult] = useState<TestResult | null>(null)
  const [testing, setTesting] = useState(false)

  function updateField(index: number, patch: Partial<TesterField>) {
    setFields((prev) => prev.map((f, i) => (i === index ? { ...f, ...patch } : f)))
  }

  async function runTest() {
    setTesting(true)
    try {
      const payload = Object.fromEntries(fields.filter((f) => f.key.trim()).map((f) => [f.key.trim(), f.value]))
      const response = await fetch(alertRoutingTestPath(), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken(),
        },
        body: JSON.stringify({ fields: payload }),
      })
      setResult(response.ok ? await response.json() : null)
    } finally {
      setTesting(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Route tester</CardTitle>
            <CardDescription className="mt-1">
              Dry-run a sample alert against the rules above. Pure evaluation, nothing is created.
            </CardDescription>
          </div>
          <Button size="sm" variant="outline" onClick={runTest} disabled={!hasPolicy || testing}>
            <IconFlask className="size-4" />
            Test
          </Button>
        </div>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          {fields.map((field, index) => (
            <div key={index} className="flex items-center gap-2">
              <Input
                value={field.key}
                onChange={(e) => updateField(index, { key: e.target.value })}
                placeholder="field"
                className="w-40"
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
          <Button
            type="button"
            variant="outline"
            size="sm"
            className="self-start"
            onClick={() => setFields((prev) => [...prev, { key: "", value: "" }])}
          >
            <IconPlus className="size-4" />
            Add field
          </Button>
        </div>

        {result && (
          <div className="flex flex-col gap-2 rounded-md border border-border bg-card p-3">
            <div className="flex items-center gap-2 text-sm">
              <Badge variant={result.matched ? "default" : "secondary"}>
                {result.matched ? "Matched" : "No match"}
              </Badge>
              {result.matched && result.outcome?.action && (
                <span className="text-muted-foreground">
                  → {ACTION_LABELS[result.outcome.action] ?? result.outcome.action}
                </span>
              )}
            </div>
            <ol className="flex flex-col gap-1 text-xs text-muted-foreground">
              {result.trace.map((entry, index) => (
                <li key={entry.rule_id} className="flex flex-wrap items-center gap-1.5">
                  <span className="font-mono">rule {index + 1}:</span>
                  <span className={entry.matched ? "text-foreground" : ""}>
                    {entry.matched ? "matched" : "did not match"}
                  </span>
                  {entry.conditions.map((condition, conditionIndex) => (
                    <span key={conditionIndex} className="font-mono">
                      [{condition.field} {condition.operator.replace(/_/g, " ")} → {condition.matched ? "✓" : "✗"}]
                    </span>
                  ))}
                </li>
              ))}
            </ol>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
