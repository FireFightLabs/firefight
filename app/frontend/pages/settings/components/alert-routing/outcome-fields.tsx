import type { InertiaFormProps } from "@inertiajs/react"

import type { IncidentSeveritySettings, WorkspaceMembership } from "@/types/serializers"
import type { SlackChannel } from "@/types"
import { OUTCOME_ACTIONS, type OutcomeAction } from "@/pages/settings/lib/alerts"
import {
  NONE_SEVERITY,
  isIncidentAction,
  type NotifyKind,
  type RuleFormData,
} from "@/pages/settings/components/alert-routing/rule-form"
import { BadgeMultiSelect } from "@/pages/settings/components/alert-routing/badge-multi-select"
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

export function OutcomeFields({
  form,
  severities,
  channels,
  members,
}: {
  form: InertiaFormProps<RuleFormData>
  severities: IncidentSeveritySettings[]
  channels: SlackChannel[]
  members: WorkspaceMembership[]
}) {
  const { data, setData } = form
  const incidentAction = isIncidentAction(data.action)

  return (
    <>
      <div className="flex flex-col gap-2">
        <Label>Then</Label>
        <div className="flex items-center gap-2">
          <Select value={data.action} onValueChange={(value) => setData("action", value as OutcomeAction)}>
            <SelectTrigger className="w-56">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {OUTCOME_ACTIONS.map((action) => (
                <SelectItem key={action.value} value={action.value}>{action.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          {incidentAction && (
            <Select value={data.severityId} onValueChange={(value) => setData("severityId", value)}>
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

      {data.action === "notify_only" && (
        <div className="flex flex-col gap-2">
          <Label>Notify</Label>
          <div className="flex items-center gap-2">
            <Select value={data.notifyKind} onValueChange={(value) => setData("notifyKind", value as NotifyKind)}>
              <SelectTrigger className="w-48">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="channel">Channel</SelectItem>
                <SelectItem value="person">Person (DM)</SelectItem>
                <SelectItem value="owning_team">Owning team's channel</SelectItem>
              </SelectContent>
            </Select>
            {data.notifyKind === "channel" && (
              channels.length > 0 ? (
                <Select
                  value={data.notifyChannel}
                  onValueChange={(value) =>
                    setData({
                      ...data,
                      notifyChannel: value,
                      notifyChannelName:
                        channels.find((channel) => channel.id === value)?.name ??
                        (value === data.notifyChannel ? data.notifyChannelName : ""),
                    })
                  }
                >
                  <SelectTrigger className="w-52">
                    <SelectValue placeholder="Pick a channel" />
                  </SelectTrigger>
                  <SelectContent>
                    {channels.map((channel) => (
                      <SelectItem key={channel.id} value={channel.id}>#{channel.name}</SelectItem>
                    ))}
                    {data.notifyChannel && !channels.some((channel) => channel.id === data.notifyChannel) && (
                      <SelectItem value={data.notifyChannel}>
                        {data.notifyChannelName ? `#${data.notifyChannelName}` : data.notifyChannel}
                      </SelectItem>
                    )}
                  </SelectContent>
                </Select>
              ) : (
                <Input
                  value={data.notifyChannel}
                  onChange={(event) => setData({ ...data, notifyChannel: event.target.value, notifyChannelName: "" })}
                  placeholder="Slack channel ID"
                  className="w-52"
                />
              )
            )}
            {data.notifyKind === "person" && (
              <Select value={data.notifyMemberId} onValueChange={(value) => setData("notifyMemberId", value)}>
                <SelectTrigger className="w-52">
                  <SelectValue placeholder="Pick a person" />
                </SelectTrigger>
                <SelectContent>
                  {members.map((member) => (
                    <SelectItem key={member.id} value={member.id}>{member.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
            {data.notifyKind === "owning_team" && (
              <span className="text-xs text-muted-foreground">
                Service's channel, else its owning team's, resolved from the catalog
              </span>
            )}
          </div>
        </div>
      )}

      {incidentAction && (
        <div className="flex flex-col gap-2">
          <Label>Invite to the incident channel</Label>
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">
              Owning team (members + manager, resolved from the alert's service)
            </span>
            <Switch checked={data.inviteOwningTeam} onCheckedChange={(checked) => setData("inviteOwningTeam", checked)} />
          </div>
          <BadgeMultiSelect
            selected={data.inviteMemberIds}
            options={members.map((member) => ({ value: member.id, label: member.name }))}
            placeholder="Add person…"
            onAdd={(id) => setData("inviteMemberIds", [ ...data.inviteMemberIds, id ])}
            onRemove={(id) => setData("inviteMemberIds", data.inviteMemberIds.filter((memberId) => memberId !== id))}
          />
        </div>
      )}
    </>
  )
}
