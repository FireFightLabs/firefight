import type { AbilityActionOption, ApprovalRule, EnvironmentOption, Principal } from "@/types/serializers"
import { APPROVAL_NOTIFY_OPTIONS, APPROVER_ROLES, type ApprovalNotifyOption, type ApproverRole } from "@/lib/generated/constants"

// Pure mapping between the approval rule dialog's form state and the
// ApprovalRule serializer/params shapes. No React in here.

// Who decides: everyone with the owner role, everyone with admin or owner,
// or the principals the rule names.
export type ApproverChoice = ApproverRole | "named"

export interface ApproverReference {
  kind: string
  id: string
}

export interface ApprovalRuleFormData {
  actionKeys: string[]
  riskLevels: string[]
  environmentIds: string[]
  approverChoice: ApproverChoice
  approvers: ApproverReference[]
  agentsMayApprove: boolean
  notify: ApprovalNotifyOption
  selfApproval: boolean
}

export const APPROVER_CHOICE_LABELS: Record<ApproverChoice, string> = {
  owner: "Anyone with the owner role",
  admin: "Anyone with the admin or owner role",
  named: "Specific people or agents",
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

export function referenceKey(reference: ApproverReference): string {
  return `${reference.kind}:${reference.id}`
}

export function parseReferenceKey(key: string): ApproverReference {
  const [kind, id] = key.split(":")
  return { kind, id }
}

export function approvalRuleFormData(rule: ApprovalRule | null): ApprovalRuleFormData {
  const role = rule && isApproverRole(rule.role) ? rule.role : "admin"
  return {
    actionKeys: rule?.actionKeys ?? [],
    riskLevels: rule?.riskLevels ?? [],
    environmentIds: rule?.environments ?? [],
    approverChoice: rule && rule.approvers.length > 0 ? "named" : role,
    approvers: rule?.approvers ?? [],
    agentsMayApprove: rule?.agentsMayApprove ?? false,
    notify: rule?.notify ?? "channel",
    selfApproval: rule?.selfApproval ?? true,
  }
}

export function hasMachineApprover(approvers: ApproverReference[]): boolean {
  return approvers.some((approver) => approver.kind !== "user")
}

export function approvalRulePayload(data: ApprovalRuleFormData) {
  const named = data.approverChoice === "named"
  return {
    rule: {
      action_keys: data.actionKeys,
      risk_levels: data.riskLevels,
      environments: data.environmentIds,
      approver_role: named ? "admin" : data.approverChoice,
      approvers: named ? data.approvers : [],
      agents_may_approve: named && hasMachineApprover(data.approvers) ? data.agentsMayApprove : false,
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

export function describeApprovers(rule: ApprovalRule, principals: Principal[]): string {
  if (rule.approvers.length > 0) {
    const names = rule.approvers.map(
      (approver) => principals.find((principal) => principal.kind === approver.kind && principal.id === approver.id)?.name ?? "a former member",
    )
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
