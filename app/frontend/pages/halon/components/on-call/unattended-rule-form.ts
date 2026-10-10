import { UNATTENDED_CAPABILITY_CHOICES, UNATTENDED_DEFAULT_METRIC, UNATTENDED_DEFAULT_MINUTES } from "@/lib/generated/constants"
import { KIND_LABELS } from "@/lib/resource-map-kinds"
import type { UnattendedRule, UnattendedRuleResource } from "@/types/serializers"

// Pure mapping between the unattended rule dialog's form state and the rule's params. No React in here.

export type UnattendedCapability = UnattendedRule["capability"]

export interface UnattendedRuleFormData {
  capability: UnattendedCapability
  resourceId: string
  metric: string
  threshold: string
  minutes: string
}

export function isCapability(value: string): value is UnattendedCapability {
  return UNATTENDED_CAPABILITY_CHOICES.some((choice) => choice.value === value)
}

export function unattendedRuleFormData(rule: UnattendedRule | null): UnattendedRuleFormData {
  return {
    capability: rule?.capability ?? "rollback",
    resourceId: rule?.resourceId ?? "",
    metric: rule?.metric ?? UNATTENDED_DEFAULT_METRIC,
    threshold: rule ? String(rule.threshold) : "",
    minutes: String(rule?.minutes ?? UNATTENDED_DEFAULT_MINUTES),
  }
}

export function unattendedRulePayload(data: UnattendedRuleFormData) {
  return {
    rule: {
      capability: data.capability,
      resource_id: data.resourceId,
      metric: data.metric,
      threshold: data.threshold,
      minutes: data.minutes,
    },
  }
}

// What a connection holding each resource can do, with the rule's own resource kept when the map no longer offers it, so
// editing a rule never drops what it names.
export function resourceOptions(resources: UnattendedRuleResource[], capability: UnattendedCapability, rule: UnattendedRule | null) {
  const options = resources
    .filter((resource) => resource.capabilities.includes(capability))
    .map((resource) => ({ value: resource.id, label: resource.name, group: KIND_LABELS[resource.kind] }))
  if (rule && !options.some((option) => option.value === rule.resourceId)) {
    options.unshift({ value: rule.resourceId, label: rule.resourceName, group: "Named by this rule" })
  }
  return options
}

export function capabilityLabel(capability: UnattendedCapability): string {
  return UNATTENDED_CAPABILITY_CHOICES.find((choice) => choice.value === capability)?.label ?? capability
}

export function dollars(cents: number): string {
  const amount = cents / 100
  return Number.isInteger(amount) ? `$${amount}` : `$${amount.toFixed(2)}`
}
