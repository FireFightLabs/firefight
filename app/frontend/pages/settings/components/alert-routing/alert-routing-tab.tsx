import { useState } from "react"
import { IconArrowDown, IconArrowUp, IconRoute } from "@tabler/icons-react"
import { router } from "@inertiajs/react"

import type { AlertRoutingPolicy, IncidentSeveritySettings, PolicyRule } from "@/types/serializers"
import {
  alertRoutingPath,
  moveDownPolicyRulePath,
  moveUpPolicyRulePath,
  policyRulePath,
} from "@/lib/routes"
import { ACTION_LABELS } from "@/pages/settings/lib/alerts"
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

export function AlertRoutingTab({
  policy,
  severities,
  prefillSource = null,
}: {
  policy: AlertRoutingPolicy | null
  severities: IncidentSeveritySettings[]
  prefillSource?: string | null
}) {
  const [editingRule, setEditingRule] = useState<PolicyRule | null>(null)
  const [addingRule, setAddingRule] = useState(() => Boolean(prefillSource))
  const rules = policy?.rules ?? []

  function togglePolicy(enabled: boolean) {
    router.patch(alertRoutingPath(), { policy: { enabled } })
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Alert routing</CardTitle>
              <CardDescription className="mt-1">
                Ordered rules evaluated top to bottom; the first match decides what happens to an alert.
                Unmatched alerts are stored but create nothing.
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
                  <TableHead className="w-24" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {rules.map((rule, index) => (
                  <TableRow key={rule.id}>
                    <TableCell className="font-mono text-xs text-muted-foreground">{index + 1}</TableCell>
                    <TableCell className="max-w-md truncate text-sm">{conditionsSummary(rule)}</TableCell>
                    <TableCell>
                      <Badge variant="outline">{ACTION_LABELS[rule.outcome.action] ?? rule.outcome.action}</Badge>
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

      <RouteTester hasPolicy={Boolean(policy)} />

      {(addingRule || editingRule) && (
        <RuleDialog
          rule={editingRule}
          severities={severities}
          prefillSource={editingRule ? null : prefillSource}
          onClose={() => {
            setAddingRule(false)
            setEditingRule(null)
          }}
        />
      )}
    </div>
  )
}
