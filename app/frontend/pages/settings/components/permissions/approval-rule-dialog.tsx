import { type FormEvent } from "react"
import { useForm } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { whenClosed } from "@/lib/handlers"
import { ABILITY_RISK_LEVELS, APPROVAL_NOTIFY_OPTIONS, APPROVER_ROLES } from "@/lib/generated/constants"
import { approvalRulePath, approvalRulesPath } from "@/lib/routes"
import { BadgeMultiSelect } from "@/pages/settings/components/alert-routing/badge-multi-select"
import { FormErrors } from "@/pages/settings/components/form-errors"
import {
  approvalRuleFormData,
  approvalRulePayload,
  isApproverRole,
  isNotifyOption,
  NOTIFY_LABELS,
  ROLE_LABELS,
  type ApprovalRuleFormData,
  type ApproverKind,
} from "@/pages/settings/components/permissions/approval-rule-form"
import type { AbilityActionOption, ApprovalRule, EnvironmentOption, WorkspaceMembership } from "@/types/serializers"

export function ApprovalRuleDialog({
  open,
  rule,
  actions,
  environments,
  members,
  onDismiss,
}: {
  open: boolean
  rule: ApprovalRule | null
  actions: AbilityActionOption[]
  environments: EnvironmentOption[]
  members: WorkspaceMembership[]
  onDismiss: () => void
}) {
  const form = useForm<ApprovalRuleFormData>(approvalRuleFormData(rule))
  const { data, setData, errors, clearErrors, processing } = form
  const needsApprovers = data.approverKind === "people" && data.approverIds.length === 0

  function patch(changes: Partial<ApprovalRuleFormData>) {
    setData((current) => ({ ...current, ...changes }))
    clearErrors()
  }

  function toggleRisk(level: string) {
    const next = data.riskLevels.includes(level)
      ? data.riskLevels.filter((value) => value !== level)
      : [ ...data.riskLevels, level ]
    patch({ riskLevels: next })
  }

  function toggleEnvironment(id: string) {
    const next = data.environmentIds.includes(id)
      ? data.environmentIds.filter((value) => value !== id)
      : [ ...data.environmentIds, id ]
    patch({ environmentIds: next })
  }

  function selectRole(value: string) {
    if (isApproverRole(value)) {
      patch({ role: value })
    }
  }

  function selectNotify(value: string) {
    if (isNotifyOption(value)) {
      patch({ notify: value })
    }
  }

  function selectApproverKind(value: string) {
    patch({ approverKind: value as ApproverKind })
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform(approvalRulePayload)
    if (rule) {
      form.patch(approvalRulePath(rule.id), { preserveScroll: true, onSuccess: onDismiss })
    } else {
      form.post(approvalRulesPath(), { preserveScroll: true, onSuccess: onDismiss })
    }
  }

  const abilityOptions = actions.map((action) => ({ value: action.key, label: action.key }))
  const memberOptions = members.map((member) => ({ value: member.id, label: member.name }))

  return (
    <Dialog open={open} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-xl">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{rule ? "Edit approval rule" : "Add approval rule"}</DialogTitle>
            <DialogDescription>
              A matching call waits until an approver says yes. Leave a question blank to match everything on it.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            <div className="flex flex-col gap-2">
              <Label>Which abilities</Label>
              <BadgeMultiSelect
                selected={data.actionKeys}
                options={abilityOptions}
                placeholder="Any ability"
                onAdd={(key) => patch({ actionKeys: [ ...data.actionKeys, key ] })}
                onRemove={(key) => patch({ actionKeys: data.actionKeys.filter((value) => value !== key) })}
              />
            </div>

            <div className="flex flex-col gap-2">
              <Label>Which risk levels</Label>
              <div className="flex flex-wrap gap-4">
                {ABILITY_RISK_LEVELS.map((level) => (
                  <label key={level} className="flex cursor-pointer items-center gap-2 text-sm">
                    <Checkbox checked={data.riskLevels.includes(level)} onCheckedChange={() => toggleRisk(level)} />
                    {level}
                  </label>
                ))}
              </div>
            </div>

            {environments.length > 0 && (
              <div className="flex flex-col gap-2">
                <Label>Which environments</Label>
                <div className="flex flex-wrap gap-4">
                  {environments.map((environment) => (
                    <label key={environment.id} className="flex cursor-pointer items-center gap-2 text-sm">
                      <Checkbox
                        checked={data.environmentIds.includes(environment.id)}
                        onCheckedChange={() => toggleEnvironment(environment.id)}
                      />
                      {environment.name}
                    </label>
                  ))}
                </div>
              </div>
            )}

            <div className="flex flex-col gap-2">
              <Label>Who approves</Label>
              <RadioGroup value={data.approverKind} onValueChange={selectApproverKind} className="gap-2">
                <div className="flex items-center gap-3">
                  <RadioGroupItem value="role" id="approver-role" />
                  <Label htmlFor="approver-role" className="font-normal">Anyone with a role</Label>
                  <Select value={data.role} onValueChange={selectRole} disabled={data.approverKind !== "role"}>
                    <SelectTrigger className="h-8 w-52">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {APPROVER_ROLES.map((role) => (
                        <SelectItem key={role} value={role}>{ROLE_LABELS[role]}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex flex-col gap-2">
                  <div className="flex items-center gap-3">
                    <RadioGroupItem value="people" id="approver-people" />
                    <Label htmlFor="approver-people" className="font-normal">Specific people</Label>
                  </div>
                  {data.approverKind === "people" && (
                    <BadgeMultiSelect
                      selected={data.approverIds}
                      options={memberOptions}
                      placeholder="Add a person"
                      onAdd={(id) => patch({ approverIds: [ ...data.approverIds, id ] })}
                      onRemove={(id) => patch({ approverIds: data.approverIds.filter((value) => value !== id) })}
                      className="ml-7"
                    />
                  )}
                </div>
              </RadioGroup>
            </div>

            <div className="flex flex-col gap-2">
              <Label>Where to ask</Label>
              <Select value={data.notify} onValueChange={selectNotify}>
                <SelectTrigger className="w-72">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {APPROVAL_NOTIFY_OPTIONS.map((option) => (
                    <SelectItem key={option} value={option}>{NOTIFY_LABELS[option]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-muted-foreground text-xs">
                Every request is also listed under Approvals, whichever you pick.
              </p>
            </div>

            <div className="flex items-center justify-between gap-4">
              <div>
                <Label htmlFor="self-approval">Requester can approve their own request</Label>
                <p className="text-muted-foreground text-xs">
                  Off means someone other than the requester has to decide.
                </p>
              </div>
              <Switch
                id="self-approval"
                checked={data.selfApproval}
                onCheckedChange={(checked) => patch({ selfApproval: checked })}
              />
            </div>
          </div>

          <FormErrors errors={errors} className="mb-3" />

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onDismiss}>Cancel</Button>
            <Button type="submit" disabled={processing || needsApprovers}>{rule ? "Save rule" : "Create rule"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
