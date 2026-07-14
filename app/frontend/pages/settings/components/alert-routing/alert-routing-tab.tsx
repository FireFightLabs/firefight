import { useState } from "react"
import { IconArrowDown, IconArrowUp, IconRoute } from "@tabler/icons-react"
import { router } from "@inertiajs/react"

import type { AlertRoutingPolicy, IncidentSeveritySettings, PolicyRule, WorkspaceMembership } from "@/types/serializers"
import {
  alertRoutingPath,
  moveDownPolicyRulePath,
  moveUpPolicyRulePath,
  policyRulePath,
} from "@/lib/routes"
import { ACTION_LABELS, type CatalogOptionMap, type SlackChannel, type TestResult } from "@/pages/settings/lib/alerts"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { RowActions } from "@/pages/settings/components/row-actions"
import { RuleDialog } from "@/pages/settings/components/alert-routing/rule-dialog"
import { RouteTester } from "@/pages/settings/components/alert-routing/route-tester"

function conditionsSummary(rule: PolicyRule): string {
  if (rule.conditions.length === 0) return "Always matches (catch-all)"

  return rule.conditions
    .map((c) => {
      const value = Array.isArray(c.value) ? c.value.join(", ") : c.value
      return value ? `${c.field} ${c.operator.replace(/_/g, " ")} ${value}` : `${c.field} ${c.operator.replace(/_/g, " ")}`
    })
    .join(" AND ")
}

function TestOutcomeBadge({ rule, testResult }: { rule: PolicyRule; testResult: TestResult | null }) {
  const entry = testResult?.trace.find((t) => t.rule_id === rule.id)
  if (!entry) return null

  if (entry.matched) {
    return <Badge className="ml-2">✓ matched</Badge>
  }
  if (entry.skipped) {
    return <span className="ml-2 text-xs text-muted-foreground/60">skipped (disabled)</span>
  }
  return <span className="ml-2 text-xs text-muted-foreground/60">✗ no match</span>
}

export function AlertRoutingTab({
  policy,
  severities,
  channels,
  members,
  catalogOptions,
  alertSource = null,
  hasWorkspaceFallback = false,
}: {
  policy: AlertRoutingPolicy | null
  severities: IncidentSeveritySettings[]
  channels: SlackChannel[]
  members: WorkspaceMembership[]
  catalogOptions: CatalogOptionMap
  alertSource?: { id: string; name: string } | null
  hasWorkspaceFallback?: boolean
}) {
  const [editingRule, setEditingRule] = useState<PolicyRule | null>(null)
  const [addingRule, setAddingRule] = useState(false)
  const [testResult, setTestResult] = useState<TestResult | null>(null)
  const rules = policy?.rules ?? []

  function togglePolicy(enabled: boolean) {
    router.patch(alertRoutingPath(), { policy: { enabled }, alert_source_id: alertSource?.id })
  }

  function toggleRule(rule: PolicyRule, enabled: boolean) {
    router.patch(policyRulePath(rule.id), { rule: { enabled } })
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>{alertSource ? `Alert routing — ${alertSource.name}` : "Default alert routing"}</CardTitle>
              <CardDescription className="mt-1">
                {alertSource
                  ? `Ordered rules for alerts from ${alertSource.name}; the first match wins. If none match, the workspace default routing applies.`
                  : "Fallback rules for sources without their own routing; the first match wins. Unmatched alerts are stored but create nothing."}
              </CardDescription>
            </div>
            <div className="flex items-center gap-4">
              {policy && (
                <div className="flex items-center gap-2">
                  <Label htmlFor="routing-enabled" className="text-sm text-muted-foreground">Enabled</Label>
                  <Switch id="routing-enabled" checked={policy.enabled} onCheckedChange={togglePolicy} />
                </div>
              )}
              <Button size="sm" onClick={() => setAddingRule(true)}>Add Rule</Button>
            </div>
          </div>
        </CardHeader>
        {rules.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="w-16">Order</TableHead>
                  <TableHead>Conditions</TableHead>
                  <TableHead className="w-48">Action</TableHead>
                  <TableHead className="w-16 text-center">On</TableHead>
                  <TableHead className="w-28" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {rules.map((rule, index) => (
                  <TableRow key={rule.id} className={rule.enabled ? "" : "opacity-50"}>
                    <TableCell className="font-mono text-xs text-muted-foreground">{index + 1}</TableCell>
                    <TableCell className="max-w-md text-sm">
                      <span className="truncate">{conditionsSummary(rule)}</span>
                      <TestOutcomeBadge rule={rule} testResult={testResult} />
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline">{ACTION_LABELS[rule.outcome.action] ?? rule.outcome.action}</Badge>
                    </TableCell>
                    <TableCell className="text-center">
                      <Switch checked={rule.enabled} onCheckedChange={(enabled) => toggleRule(rule, enabled)} />
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center justify-end gap-0.5">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="size-7 text-muted-foreground"
                          disabled={index === 0}
                          onClick={() => router.patch(moveUpPolicyRulePath(rule.id))}
                        >
                          <IconArrowUp className="size-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="size-7 text-muted-foreground"
                          disabled={index === rules.length - 1}
                          onClick={() => router.patch(moveDownPolicyRulePath(rule.id))}
                        >
                          <IconArrowDown className="size-4" />
                        </Button>
                        <RowActions
                          onEdit={() => setEditingRule(rule)}
                          onDelete={() => router.delete(policyRulePath(rule.id))}
                        />
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <div className="flex items-center gap-3 text-sm text-muted-foreground">
              <IconRoute className="size-4" />
              No routing rules yet. Without a matching rule, incoming alerts are stored but never create incidents.
            </div>
          </CardContent>
        )}
      </Card>

      <RouteTester
        hasPolicy={Boolean(policy) || (Boolean(alertSource) && hasWorkspaceFallback)}
        alertSourceId={alertSource?.id ?? null}
        onResult={setTestResult}
      />

      {(addingRule || editingRule) && (
        <RuleDialog
          rule={editingRule}
          severities={severities}
          channels={channels}
          members={members}
          catalogOptions={catalogOptions}
          alertSourceId={alertSource?.id ?? null}
          onClose={() => {
            setAddingRule(false)
            setEditingRule(null)
          }}
        />
      )}
    </div>
  )
}
