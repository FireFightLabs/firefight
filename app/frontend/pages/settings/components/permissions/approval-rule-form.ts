import type { AbilityActionOption, ApprovalRule, EnvironmentOption, WorkspaceMembership } from "@/types/serializers"
import { APPROVAL_NOTIFY_OPTIONS, APPROVER_ROLES, type ApprovalNotifyOption, type ApproverRole } from "@/lib/generated/constants"

// Pure mapping between the approval rule dialog's form state and the
// ApprovalRule serializer/params shapes. No React in here.

export type ApproverKind = "role" | "people"

export interface ApprovalRuleFormData {
  actionKeys: string[]
  riskLevels: string[]
  environmentIds: string[]
  approverKind: ApproverKind
  role: ApproverRole
  approverIds: string[]
  notify: ApprovalNotifyOption
  selfApproval: boolean
}

export const NOTIFY_LABELS: Record<ApprovalNotifyOption, string> = {
  channel: "Incidents channel",
  dm: "Direct message to each approver",
  both: "Both",
}

export const ROLE_LABELS: Record<ApproverRole, string> = {
  admin: "Any admin or owner",
  owner: "Any owner",
}

export function isNotifyOption(value: string): value is ApprovalNotifyOption {
  return (APPROVAL_NOTIFY_OPTIONS as readonly string[]).includes(value)
}

export function isApproverRole(value: string): value is ApproverRole {
  return (APPROVER_ROLES as readonly string[]).includes(value)
}

export function approvalRuleFormData(rule: ApprovalRule | null): ApprovalRuleFormData {
  const role = rule && isApproverRole(rule.role) ? rule.role : "admin"
  return {
    actionKeys: rule?.actionKeys ?? [],
    riskLevels: rule?.riskLevels ?? [],
    environmentIds: rule?.environments ?? [],
    approverKind: rule && rule.approverIds.length > 0 ? "people" : "role",
    role,
    approverIds: rule?.approverIds ?? [],
    notify: rule?.notify ?? "channel",
    selfApproval: rule?.selfApproval ?? true,
  }
}

export function approvalRulePayload(data: ApprovalRuleFormData) {
  return {
    rule: {
      action_keys: data.actionKeys,
      risk_levels: data.riskLevels,
      environments: data.environmentIds,
      approver_role: data.role,
      approvers: data.approverKind === "people" ? data.approverIds : [],
      notify: data.notify,
      self_approval: data.selfApproval,
    },
  }
}

function listOf(names: string[]): string {
  if (names.length <= 2) {
    return names.join(" and ")
  }
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
}

// One sentence per rule, the way an admin would say it out loud.
export function describeScope(rule: ApprovalRule, environments: EnvironmentOption[]): string {
  const parts: string[] = []
  if (rule.actionKeys.length > 0) {
    parts.push(listOf(rule.actionKeys))
  } else if (rule.riskLevels.length > 0) {
    parts.push(`every ${listOf(rule.riskLevels)} ability`)
  } else {
    parts.push("every ability")
  }
  if (rule.actionKeys.length > 0 && rule.riskLevels.length > 0) {
    parts.push(`when ${listOf(rule.riskLevels)}`)
  }
  if (rule.environments.length > 0) {
    const names = rule.environments.map((id) => environments.find((environment) => environment.id === id)?.name ?? id)
    parts.push(`in ${listOf(names)}`)
  }
  return parts.join(" ")
}

export function describeApprovers(rule: ApprovalRule, members: WorkspaceMembership[]): string {
  if (rule.approverIds.length > 0) {
    const names = rule.approverIds.map((id) => members.find((member) => member.id === id)?.name ?? "a former member")
    return listOf(names)
  }
  return isApproverRole(rule.role) ? ROLE_LABELS[rule.role].toLowerCase() : rule.role
}

// Whether any enabled rule would hold this ability somewhere. Environments
// are ignored on purpose. A rule scoped to production still marks the ability,
// since that is what an admin handing it out needs to know.
export function requiresApproval(action: AbilityActionOption, rules: ApprovalRule[]): boolean {
  if (action.approvalExempt) {
    return false
  }
  return rules.some((rule) => {
    if (!rule.enabled) {
      return false
    }
    const abilityMatches = rule.actionKeys.length === 0 || rule.actionKeys.includes(action.key)
    const riskMatches = rule.riskLevels.length === 0 || rule.riskLevels.includes(action.riskLevel)
    return abilityMatches && riskMatches
  })
}
