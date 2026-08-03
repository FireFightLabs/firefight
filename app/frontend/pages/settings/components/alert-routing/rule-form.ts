import type { PolicyRule } from "@/types/serializers"
import {
  TARGET_CHANNEL,
  TARGET_MEMBER,
  TARGET_OWNING_TEAM,
  type ConditionOperator,
  type OutcomeAction,
} from "@/pages/settings/lib/alerts"

// Pure mapping between the rule dialog's form state and the PolicyRule
// serializer/params shapes; no React in here.

export const NONE_SEVERITY = "none"

export type NotifyKind = "channel" | "person" | "owning_team"

export interface ConditionRow {
  field: string
  operator: ConditionOperator
  value: string
}

export interface RuleFormData {
  conditions: ConditionRow[]
  action: OutcomeAction
  severityId: string
  notifyKind: NotifyKind
  notifyChannel: string
  notifyChannelName: string
  notifyMemberId: string
  inviteOwningTeam: boolean
  inviteMemberIds: string[]
}

export function isIncidentAction(action: OutcomeAction): boolean {
  return action === "auto_create_incident" || action === "attach_to_incident"
}

export function conditionValues(condition: ConditionRow): string[] {
  return condition.value.split(",").map((value) => value.trim()).filter(Boolean)
}

export function ruleFormData(rule: PolicyRule | null): RuleFormData {
  const outcome = rule?.outcome
  return {
    conditions: (rule?.conditions ?? []).map((condition) => ({
      field: condition.field,
      operator: condition.operator,
      value: Array.isArray(condition.value) ? condition.value.join(", ") : (condition.value ?? ""),
    })),
    action: outcome?.action ?? "auto_create_incident",
    severityId: outcome?.severityId ?? NONE_SEVERITY,
    notifyKind:
      outcome?.notify?.type === TARGET_MEMBER
        ? "person"
        : outcome?.notify?.type === TARGET_OWNING_TEAM
          ? "owning_team"
          : "channel",
    notifyChannel: outcome?.notify?.channelId ?? "",
    notifyChannelName: outcome?.notify?.channelName ?? "",
    notifyMemberId: outcome?.notify?.memberId ?? "",
    inviteOwningTeam: outcome?.invite?.some((item) => item.type === TARGET_OWNING_TEAM) ?? false,
    inviteMemberIds: outcome?.invite?.flatMap((item) => (item.type === TARGET_MEMBER && item.memberId ? [ item.memberId ] : [])) ?? [],
  }
}

function conditionPayload(condition: ConditionRow) {
  const base = { field: condition.field.trim(), operator: condition.operator }
  if (condition.operator === "is_empty") {
    return base
  }
  if (condition.operator === "is_one_of") {
    return { ...base, value: conditionValues(condition) }
  }
  return { ...base, value: condition.value }
}

function notifyPayload(data: RuleFormData) {
  if (data.action !== "notify_only") {
    return {}
  }
  if (data.notifyKind === "owning_team") {
    return { notify: { type: TARGET_OWNING_TEAM, of: "service" } }
  }
  if (data.notifyKind === "person" && data.notifyMemberId) {
    return { notify: { type: TARGET_MEMBER, member_id: data.notifyMemberId } }
  }
  if (data.notifyKind === "channel" && data.notifyChannel.trim()) {
    return {
      notify: {
        type: TARGET_CHANNEL,
        channel_id: data.notifyChannel.trim(),
        // Display-only label captured at config time; the ID stays canonical.
        ...(data.notifyChannelName.trim() ? { channel_name: data.notifyChannelName.trim() } : {}),
      },
    }
  }
  return {}
}

function invitePayload(data: RuleFormData) {
  if (!isIncidentAction(data.action)) {
    return {}
  }
  const targets = [
    ...(data.inviteOwningTeam ? [{ type: TARGET_OWNING_TEAM, of: "service" }] : []),
    ...data.inviteMemberIds.map((id) => ({ type: TARGET_MEMBER, member_id: id })),
  ]
  return targets.length > 0 ? { invite: targets } : {}
}

export function rulePayload(data: RuleFormData, alertSourceId: string | null) {
  return {
    alert_source_id: alertSourceId,
    rule: {
      conditions: data.conditions.filter((condition) => condition.field.trim()).map(conditionPayload),
      outcome: {
        action: data.action,
        ...(data.severityId !== NONE_SEVERITY ? { severity_id: data.severityId } : {}),
        ...notifyPayload(data),
        ...invitePayload(data),
      },
    },
  }
}
