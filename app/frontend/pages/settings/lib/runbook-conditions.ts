import type IncidentConditionSettings from "@/types/IncidentConditionSettings"
import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
} from "@/types/serializers"

export const CONDITION_FIELD_INCIDENT_TYPE = "incident_type"
export const CONDITION_FIELD_SEVERITY = "severity"
export const CONDITION_FIELD_CUSTOM_FIELD = "custom_field"
export const OPERATOR_ONE_OF = "one_of"
export const OPERATOR_NOT_ONE_OF = "not_one_of"

type FixedConditionField = typeof CONDITION_FIELD_INCIDENT_TYPE | typeof CONDITION_FIELD_SEVERITY

const FIELD_LABELS: Record<FixedConditionField, string> = {
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
  customFields: RunbookCustomField[],
): string | null {
  if (!conditions.length) return null

  const typeMap = new Map(incidentTypes.map((t) => [t.id, t.name]))
  const severityMap = new Map(severities.map((s) => [s.id, s.name]))
  const fieldMap = new Map(customFields.map((f) => [f.id, f]))

  return conditions
    .map((c) => {
      const operatorLabel = OPERATOR_LABELS[c.operator] ?? c.operator

      if (c.conditionField === CONDITION_FIELD_CUSTOM_FIELD) {
        const field = c.incidentFieldDefinitionId ? fieldMap.get(c.incidentFieldDefinitionId) : undefined
        const valueMap = new Map(
          field ? valueOptions(field).map((o) => [o.id, o.name]) : [],
        )
        const names = c.values.map((v) => valueMap.get(v) ?? v).join(", ")
        return `${field?.name ?? "Custom field"} ${operatorLabel} ${names}`
      }

      const map = c.conditionField === CONDITION_FIELD_SEVERITY ? severityMap : typeMap
      const fieldLabel = FIELD_LABELS[c.conditionField as FixedConditionField] ?? c.conditionField
      const names = c.values.map((v) => map.get(v) ?? v).join(", ")
      return `${fieldLabel} ${operatorLabel} ${names}`
    })
    .join(" AND ")
}

export function valueOptions(field: RunbookCustomField): { id: string; name: string }[] {
  if (field.entries.length > 0) {
    return field.entries.map((e) => ({ id: e.id, name: e.name }))
  }
  return field.options.map((o) => ({ id: o, name: o }))
}
