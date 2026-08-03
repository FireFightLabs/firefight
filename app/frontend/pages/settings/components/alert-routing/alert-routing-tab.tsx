import { useState } from "react"
import { IconArrowDown, IconArrowUp, IconFlask, IconRoute } from "@tabler/icons-react"
import { router } from "@inertiajs/react"

import type { AlertRoutingPolicy, IncidentSeveritySettings, PolicyRule, WorkspaceMembership } from "@/types/serializers"
import {
  alertRoutingPath,
  moveDownPolicyRulePath,
  moveUpPolicyRulePath,
  policyRulePath,
} from "@/lib/routes"
import {
  ACTION_LABELS,
  describeSample,
  needsCustomSample,
  runRoutingTest,
  sampleFieldsFor,
  type CatalogOptionMap,
  type TestResult,
} from "@/pages/settings/lib/alerts"
import type { SlackChannel } from "@/types"
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
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { GroupingSettings } from "@/pages/settings/components/alert-routing/grouping-settings"
import { RuleDialog } from "@/pages/settings/components/alert-routing/rule-dialog"
import { CustomTestDialog } from "@/pages/settings/components/alert-routing/custom-test-dialog"
import { TestOutcomeBadge } from "@/pages/settings/components/alert-routing/test-outcome-badge"

function conditionsSummary(rule: PolicyRule): string {
  if (rule.conditions.length === 0) {
    return "Always matches"
  }

  return rule.conditions
    .map((condition) => {
      const value = Array.isArray(condition.value) ? condition.value.join(", ") : condition.value
      return value ? `${condition.field} ${condition.operator.replace(/_/g, " ")} ${value}` : `${condition.field} ${condition.operator.replace(/_/g, " ")}`
    })
    .join(" AND ")
}

export function AlertRoutingTab({
  policy,
  severities,
  channels,
  members,
  catalogOptions,
  alertSource,
  hasWorkspaceFallback,
}: {
  policy: AlertRoutingPolicy | null
  severities: IncidentSeveritySettings[]
  channels: SlackChannel[]
  members: WorkspaceMembership[]
  catalogOptions: CatalogOptionMap
  alertSource: { id: string; name: string } | null
  hasWorkspaceFallback: boolean
}) {
  const alertSourceId = alertSource?.id ?? null
  const [editingRule, setEditingRule] = useState<PolicyRule | null>(null)
  const [addingRule, setAddingRule] = useState(false)
  const [deletingRule, setDeletingRule] = useState<PolicyRule | null>(null)
  const [testResult, setTestResult] = useState<TestResult | null>(null)
  const [testError, setTestError] = useState<string | null>(null)
  const [testedRuleId, setTestedRuleId] = useState<string | null>(null)
  const [testedSample, setTestedSample] = useState<string | null>(null)
  const rules = policy?.rules ?? []
  const canTest = Boolean(policy) || (Boolean(alertSource) && hasWorkspaceFallback)

  function clearTest() {
    setTestResult(null)
    setTestError(null)
    setTestedRuleId(null)
    setTestedSample(null)
  }

  async function testRule(rule: PolicyRule) {
    const sample = sampleFieldsFor(rule.conditions)
    setTestedRuleId(rule.id)
    setTestedSample(describeSample(sample))
    const { result, error } = await runRoutingTest(sample, alertSourceId)
    setTestResult(result)
    setTestError(error)
  }

  function shadowNote(rule: PolicyRule): string | null {
    if (!testResult || testedRuleId !== rule.id) {
      return null
    }
    const winnerIndex = testResult.trace.findIndex((trace) => trace.matched)
    if (winnerIndex === -1 || testResult.trace[winnerIndex]?.rule_id === rule.id) {
      return null
    }
    return `a sample for this rule is captured by rule ${winnerIndex + 1} first`
  }

  function togglePolicy(enabled: boolean) {
    clearTest()
    router.patch(alertRoutingPath(), { policy: { enabled }, alert_source_id: alertSourceId })
  }

  function toggleRule(rule: PolicyRule, enabled: boolean) {
    clearTest()
    router.patch(policyRulePath(rule.id), { rule: { enabled } })
  }

  function moveRule(rule: PolicyRule, direction: "up" | "down") {
    clearTest()
    router.patch(direction === "up" ? moveUpPolicyRulePath(rule.id) : moveDownPolicyRulePath(rule.id))
  }

  function confirmDeleteRule() {
    if (!deletingRule) {
      return
    }
    clearTest()
    router.delete(policyRulePath(deletingRule.id))
    setDeletingRule(null)
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>{alertSource ? `Alert routing for ${alertSource.name}` : "Default alert routing"}</CardTitle>
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
              <CustomTestDialog disabled={!canTest} alertSourceId={alertSourceId} />
              <Button size="sm" onClick={() => setAddingRule(true)}>Add rule</Button>
            </div>
          </div>
          {(testedSample || testError) && (
            <div className="mt-2 text-xs">
              {testError ? (
                <span className="text-destructive">{testError}</span>
              ) : (
                <span className="text-muted-foreground">Tested with {testedSample}</span>
              )}
            </div>
          )}
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
                {rules.map((rule, index) => {
                  const regexRule = needsCustomSample(rule.conditions)
                  return (
                    <TableRow key={rule.id} className={rule.enabled ? "" : "opacity-50"}>
                      <TableCell className="font-mono text-xs text-muted-foreground">{index + 1}</TableCell>
                      <TableCell className="max-w-md text-sm">
                        <span className="truncate">{conditionsSummary(rule)}</span>
                        <TestOutcomeBadge rule={rule} testResult={testResult} />
                        {shadowNote(rule) && (
                          <span className="ml-2 text-xs text-amber-500/80">⚠ {shadowNote(rule)}</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">{ACTION_LABELS[rule.outcome.action] ?? rule.outcome.action}</Badge>
                      </TableCell>
                      <TableCell className="text-center">
                        <Switch
                          checked={rule.enabled}
                          onCheckedChange={(enabled) => toggleRule(rule, enabled)}
                          aria-label={`Rule ${index + 1} enabled`}
                        />
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center justify-end gap-0.5">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="size-7 text-muted-foreground"
                            title={regexRule ? "Regex rules need a real sample value; use Test custom alert" : "Test this rule"}
                            aria-label="Test this rule"
                            disabled={!canTest || regexRule}
                            onClick={() => void testRule(rule)}
                          >
                            <IconFlask className="size-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="size-7 text-muted-foreground"
                            title="Move up"
                            aria-label="Move rule up"
                            disabled={index === 0}
                            onClick={() => moveRule(rule, "up")}
                          >
                            <IconArrowUp className="size-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="size-7 text-muted-foreground"
                            title="Move down"
                            aria-label="Move rule down"
                            disabled={index === rules.length - 1}
                            onClick={() => moveRule(rule, "down")}
                          >
                            <IconArrowDown className="size-4" />
                          </Button>
                          <RowActions
                            onEdit={() => setEditingRule(rule)}
                            onDelete={() => setDeletingRule(rule)}
                          />
                        </div>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <div className="flex items-center justify-between gap-3">
              <div className="flex items-center gap-3 text-sm text-muted-foreground">
                <IconRoute className="size-4" />
                No routing rules yet. Without a matching rule, incoming alerts are stored but never create incidents.
              </div>
              <Button size="sm" variant="outline" onClick={() => setAddingRule(true)}>Add your first rule</Button>
            </div>
          </CardContent>
        )}
      </Card>

      {policy && <GroupingSettings policy={policy} alertSourceId={alertSourceId} />}

      {(addingRule || editingRule) && (
        <RuleDialog
          rule={editingRule}
          severities={severities}
          channels={channels}
          members={members}
          catalogOptions={catalogOptions}
          alertSourceId={alertSourceId}
          onClose={() => {
            clearTest()
            setAddingRule(false)
            setEditingRule(null)
          }}
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deletingRule)}
        title="Delete this rule?"
        description="Alerts that only this rule matches will fall through to later rules, or go unmatched and create nothing."
        onConfirm={confirmDeleteRule}
        onCancel={() => setDeletingRule(null)}
      />
    </div>
  )
}
