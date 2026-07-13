import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import { IconPlus, IconTrash } from "@tabler/icons-react"

import type { IncidentSeveritySettings, PolicyRule } from "@/types/serializers"
import { policyRulePath, policyRulesPath } from "@/lib/routes"
import {
  CONDITION_OPERATORS,
  OUTCOME_ACTIONS,
  type ConditionOperator,
  type OutcomeAction,
} from "@/pages/settings/lib/alerts"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

const NONE_SEVERITY = "none"

interface ConditionRow {
  field: string
  operator: ConditionOperator
  value: string
}

function toRows(rule: PolicyRule | null): ConditionRow[] {
  if (!rule) return []

  return rule.conditions.map((c) => ({
    field: c.field,
    operator: c.operator as ConditionOperator,
    value: Array.isArray(c.value) ? c.value.join(", ") : (c.value ?? ""),
  }))
}

export function RuleDialog({
  rule,
  severities,
  onClose,
  alertSourceId = null,
}: {
  rule: PolicyRule | null
  severities: IncidentSeveritySettings[]
  onClose: () => void
  alertSourceId?: string | null
}) {
  const [conditions, setConditions] = useState<ConditionRow[]>(() => toRows(rule))
  const [action, setAction] = useState<OutcomeAction>((rule?.outcome.action as OutcomeAction) ?? "auto_create_incident")
  const [severityId, setSeverityId] = useState(rule?.outcome.severityId ?? NONE_SEVERITY)
  const [channel, setChannel] = useState(rule?.outcome.channel ?? "")

  function updateCondition(index: number, patch: Partial<ConditionRow>) {
    setConditions((prev) => prev.map((c, i) => (i === index ? { ...c, ...patch } : c)))
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()

    const payload = {
      alert_source_id: alertSourceId,
      rule: {
        conditions: conditions
          .filter((c) => c.field.trim())
          .map((c) => ({
            field: c.field.trim(),
            operator: c.operator,
            ...(c.operator === "is_empty"
              ? {}
              : c.operator === "is_one_of"
                ? { value: c.value.split(",").map((v) => v.trim()).filter(Boolean) }
                : { value: c.value }),
          })),
        outcome: {
          action,
          ...(severityId !== NONE_SEVERITY ? { severity_id: severityId } : {}),
          ...(action === "notify_only" && channel.trim() ? { channel: channel.trim() } : {}),
        },
      },
    }

    if (rule) {
      router.patch(policyRulePath(rule.id), payload, { onSuccess: onClose })
    } else {
      router.post(policyRulesPath(), payload, { onSuccess: onClose })
    }
  }

  return (
    <Dialog open onOpenChange={(isOpen) => !isOpen && onClose()}>
      <DialogContent className="sm:max-w-xl">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>{rule ? "Edit rule" : "Add rule"}</DialogTitle>
            <DialogDescription>
              All conditions must match (AND). A rule with no conditions matches every alert.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            <div className="flex flex-col gap-2">
              <Label>Conditions</Label>
              {conditions.map((condition, index) => (
                <div key={index} className="flex items-center gap-2">
                  <Input
                    value={condition.field}
                    onChange={(e) => updateCondition(index, { field: e.target.value })}
                    placeholder="field, e.g. service"
                    className="w-36"
                  />
                  <Select
                    value={condition.operator}
                    onValueChange={(value) => updateCondition(index, { operator: value as ConditionOperator })}
                  >
                    <SelectTrigger className="w-36">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {CONDITION_OPERATORS.map((op) => (
                        <SelectItem key={op.value} value={op.value}>{op.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {condition.operator !== "is_empty" && (
                    <Input
                      value={condition.value}
                      onChange={(e) => updateCondition(index, { value: e.target.value })}
                      placeholder={condition.operator === "is_one_of" ? "comma-separated values" : "value"}
                      className="flex-1"
                    />
                  )}
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="size-8 text-muted-foreground"
                    onClick={() => setConditions((prev) => prev.filter((_, i) => i !== index))}
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
                onClick={() => setConditions((prev) => [...prev, { field: "", operator: "is_one_of", value: "" }])}
              >
                <IconPlus className="size-4" />
                Add condition
              </Button>
            </div>

            <div className="flex flex-col gap-2">
              <Label>Then</Label>
              <div className="flex items-center gap-2">
                <Select value={action} onValueChange={(value) => setAction(value as OutcomeAction)}>
                  <SelectTrigger className="w-56">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {OUTCOME_ACTIONS.map((a) => (
                      <SelectItem key={a.value} value={a.value}>{a.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {(action === "auto_create_incident" || action === "attach_to_incident") && (
                  <Select value={severityId} onValueChange={setSeverityId}>
                    <SelectTrigger className="w-48">
                      <SelectValue placeholder="Severity" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value={NONE_SEVERITY}>Severity from source map</SelectItem>
                      {severities.map((severity) => (
                        <SelectItem key={severity.id} value={severity.id}>{severity.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
                {action === "notify_only" && (
                  <Input
                    value={channel}
                    onChange={(e) => setChannel(e.target.value)}
                    placeholder="Slack channel ID"
                    className="w-48"
                  />
                )}
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit">{rule ? "Save rule" : "Create rule"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
