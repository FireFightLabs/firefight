import type IncidentConditionSettings from "@/types/IncidentConditionSettings"
import type { IncidentSeveritySettings, IncidentTypeSettings } from "@/types/serializers"

export const CONDITION_FIELD_INCIDENT_TYPE = "incident_type"
export const CONDITION_FIELD_SEVERITY = "severity"
export const OPERATOR_ONE_OF = "one_of"
export const OPERATOR_NOT_ONE_OF = "not_one_of"

type ConditionField = typeof CONDITION_FIELD_INCIDENT_TYPE | typeof CONDITION_FIELD_SEVERITY

const FIELD_LABELS: Record<ConditionField, string> = {
  [CONDITION_FIELD_INCIDENT_TYPE]: "Incident Type",
  [CONDITION_FIELD_SEVERITY]: "Severity",
}

const OPERATOR_LABELS: Record<string, string> = {
  [OPERATOR_ONE_OF]: "is one of",
  [OPERATOR_NOT_ONE_OF]: "is not one of",
}

export function conditionSummary(
  conditions: IncidentConditionSettings[],
  incidentTypes: IncidentTypeSettings[],
  severities: IncidentSeveritySettings[],
): string | null {
  if (!conditions.length) return null

  const typeMap = new Map(incidentTypes.map((t) => [t.id, t.name]))
  const severityMap = new Map(severities.map((s) => [s.id, s.name]))

  return conditions
    .map((c) => {
      const map = c.conditionField === CONDITION_FIELD_SEVERITY ? severityMap : typeMap
      const fieldLabel = FIELD_LABELS[c.conditionField as ConditionField] ?? c.conditionField
      const names = c.values.map((v) => map.get(v) ?? v).join(", ")
      const operatorLabel = OPERATOR_LABELS[c.operator] ?? c.operator
      return `${fieldLabel} ${operatorLabel} ${names}`
    })
    .join(" AND ")
}
