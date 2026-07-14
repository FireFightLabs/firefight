import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import { IconPlus, IconTrash, IconX } from "@tabler/icons-react"

import type { IncidentSeveritySettings, PolicyRule, WorkspaceMembership } from "@/types/serializers"
import { policyRulePath, policyRulesPath } from "@/lib/routes"
import {
  CONDITION_OPERATORS,
  OUTCOME_ACTIONS,
  type ConditionOperator,
  type OutcomeAction,
  type SlackChannel,
} from "@/pages/settings/lib/alerts"
import { Badge } from "@/components/ui/badge"
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
import { Switch } from "@/components/ui/switch"

const NONE_SEVERITY = "none"

type NotifyKind = "channel" | "person" | "owning_team"

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
  channels,
  members,
  onClose,
  alertSourceId = null,
}: {
  rule: PolicyRule | null
  severities: IncidentSeveritySettings[]
  channels: SlackChannel[]
  members: WorkspaceMembership[]
  onClose: () => void
  alertSourceId?: string | null
}) {
  const outcome = rule?.outcome
  const [conditions, setConditions] = useState<ConditionRow[]>(() => toRows(rule))
  const [action, setAction] = useState<OutcomeAction>((outcome?.action as OutcomeAction) ?? "auto_create_incident")
  const [severityId, setSeverityId] = useState(outcome?.severityId ?? NONE_SEVERITY)

  const [notifyKind, setNotifyKind] = useState<NotifyKind>(() => {
    if (outcome?.notify?.type === "member") return "person"
    if (outcome?.notify?.type === "owning_team") return "owning_team"
    return "channel"
  })
  const [notifyChannel, setNotifyChannel] = useState(outcome?.notify?.channelId ?? "")
  const [notifyMemberId, setNotifyMemberId] = useState(outcome?.notify?.memberId ?? "")

  const [inviteOwningTeam, setInviteOwningTeam] = useState(
    () => outcome?.invite?.some((t) => t.type === "owning_team") ?? false
  )
  const [inviteMemberIds, setInviteMemberIds] = useState<string[]>(
    () => outcome?.invite?.filter((t) => t.type === "member").map((t) => t.memberId as string) ?? []
  )

  const isIncidentAction = action === "auto_create_incident" || action === "attach_to_incident"
  const availableMembers = members.filter((m) => !inviteMemberIds.includes(m.id))

  function updateCondition(index: number, patch: Partial<ConditionRow>) {
    setConditions((prev) => prev.map((c, i) => (i === index ? { ...c, ...patch } : c)))
  }

  function buildNotify() {
    if (action !== "notify_only") return {}
    if (notifyKind === "owning_team") return { notify: { type: "owning_team", of: "service" } }
    if (notifyKind === "person" && notifyMemberId) return { notify: { type: "member", member_id: notifyMemberId } }
    if (notifyKind === "channel" && notifyChannel.trim()) return { notify: { type: "channel", channel_id: notifyChannel.trim() } }
    return {}
  }

  function buildInvite() {
    if (!isIncidentAction) return {}
    const targets = [
      ...(inviteOwningTeam ? [{ type: "owning_team", of: "service" }] : []),
      ...inviteMemberIds.map((id) => ({ type: "member", member_id: id })),
    ]
    return targets.length > 0 ? { invite: targets } : {}
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
          ...buildNotify(),
          ...buildInvite(),
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
                {isIncidentAction && (
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
              </div>
            </div>

            {action === "notify_only" && (
              <div className="flex flex-col gap-2">
                <Label>Notify</Label>
                <div className="flex items-center gap-2">
                  <Select value={notifyKind} onValueChange={(value) => setNotifyKind(value as NotifyKind)}>
                    <SelectTrigger className="w-48">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="channel">Channel</SelectItem>
                      <SelectItem value="person">Person (DM)</SelectItem>
                      <SelectItem value="owning_team">Owning team's channel</SelectItem>
                    </SelectContent>
                  </Select>
                  {notifyKind === "channel" && (
                    channels.length > 0 ? (
                      <Select value={notifyChannel} onValueChange={setNotifyChannel}>
                        <SelectTrigger className="w-52">
                          <SelectValue placeholder="Pick a channel" />
                        </SelectTrigger>
                        <SelectContent>
                          {channels.map((c) => (
                            <SelectItem key={c.id} value={c.id}>#{c.name}</SelectItem>
                          ))}
                          {notifyChannel && !channels.some((c) => c.id === notifyChannel) && (
                            <SelectItem value={notifyChannel}>{notifyChannel}</SelectItem>
                          )}
                        </SelectContent>
                      </Select>
                    ) : (
                      <Input
                        value={notifyChannel}
                        onChange={(e) => setNotifyChannel(e.target.value)}
                        placeholder="Slack channel ID"
                        className="w-52"
                      />
                    )
                  )}
                  {notifyKind === "person" && (
                    <Select value={notifyMemberId} onValueChange={setNotifyMemberId}>
                      <SelectTrigger className="w-52">
                        <SelectValue placeholder="Pick a person" />
                      </SelectTrigger>
                      <SelectContent>
                        {members.map((m) => (
                          <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                  {notifyKind === "owning_team" && (
                    <span className="text-xs text-muted-foreground">
                      Service's channel, else its owning team's — resolved from the catalog
                    </span>
                  )}
                </div>
              </div>
            )}

            {isIncidentAction && (
              <div className="flex flex-col gap-2">
                <Label>Invite to the incident channel</Label>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">
                    Owning team (members + manager, resolved from the alert's service)
                  </span>
                  <Switch checked={inviteOwningTeam} onCheckedChange={setInviteOwningTeam} />
                </div>
                <div className="flex flex-wrap items-center gap-1.5">
                  {inviteMemberIds.map((id) => {
                    const member = members.find((m) => m.id === id)
                    return (
                      <Badge key={id} variant="secondary" className="gap-1">
                        {member?.name ?? id}
                        <button
                          type="button"
                          onClick={() => setInviteMemberIds((prev) => prev.filter((v) => v !== id))}
                          className="ml-0.5"
                        >
                          <IconX className="size-3" />
                        </button>
                      </Badge>
                    )
                  })}
                  {availableMembers.length > 0 && (
                    <Select value="" onValueChange={(id) => setInviteMemberIds((prev) => [...prev, id])}>
                      <SelectTrigger className="h-7 w-40 text-xs">
                        <SelectValue placeholder="Add person…" />
                      </SelectTrigger>
                      <SelectContent>
                        {availableMembers.map((m) => (
                          <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </div>
              </div>
            )}
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
