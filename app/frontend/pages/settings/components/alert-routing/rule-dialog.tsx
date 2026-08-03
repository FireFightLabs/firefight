import { type FormEvent } from "react"
import { useForm } from "@inertiajs/react"

import type { IncidentSeveritySettings, PolicyRule, WorkspaceMembership } from "@/types/serializers"
import { policyRulePath, policyRulesPath } from "@/lib/routes"
import type { SlackChannel } from "@/types"
import { type CatalogOptionMap } from "@/pages/settings/lib/alerts"
import { rowListOps } from "@/pages/settings/lib/row-list"
import {
  ruleFormData,
  rulePayload,
  type ConditionRow,
  type RuleFormData,
} from "@/pages/settings/components/alert-routing/rule-form"
import { ConditionRowFields } from "@/pages/settings/components/alert-routing/condition-row"
import { OutcomeFields } from "@/pages/settings/components/alert-routing/outcome-fields"
import { FormErrors } from "@/pages/settings/components/form-errors"
import { AddRowButton } from "@/pages/settings/components/row-list-buttons"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"

export function RuleDialog({
  rule,
  severities,
  channels,
  members,
  catalogOptions,
  onClose,
  alertSourceId,
}: {
  rule: PolicyRule | null
  severities: IncidentSeveritySettings[]
  channels: SlackChannel[]
  members: WorkspaceMembership[]
  catalogOptions: CatalogOptionMap
  onClose: () => void
  alertSourceId: string | null
}) {
  const form = useForm<RuleFormData>(ruleFormData(rule))
  const conditions = rowListOps<ConditionRow>(form.data.conditions, (rows) => form.setData("conditions", rows))

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => rulePayload(data, alertSourceId))
    if (rule) {
      form.patch(policyRulePath(rule.id), { onSuccess: onClose })
    } else {
      form.post(policyRulesPath(), { onSuccess: onClose })
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
              {form.data.conditions.map((condition, index) => (
                <ConditionRowFields
                  key={index}
                  condition={condition}
                  catalogOptions={catalogOptions}
                  onChange={(patch) => conditions.update(index, patch)}
                  onRemove={() => conditions.remove(index)}
                />
              ))}
              <AddRowButton
                label="Add condition"
                onClick={() => conditions.append({ field: "", operator: "is_one_of", value: "" })}
              />
            </div>

            <OutcomeFields form={form} severities={severities} channels={channels} members={members} />
          </div>

          <FormErrors errors={form.errors} className="mb-3" />

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={form.processing}>{rule ? "Save rule" : "Create rule"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
