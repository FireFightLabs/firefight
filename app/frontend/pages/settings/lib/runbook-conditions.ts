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
  if (!conditions.length) {
    return null
  }

  const typeMap = new Map(incidentTypes.map((type) => [type.id, type.name]))
  const severityMap = new Map(severities.map((severity) => [severity.id, severity.name]))
  const fieldMap = new Map(customFields.map((field) => [field.id, field]))

  return conditions
    .map((condition) => {
      const operatorLabel = OPERATOR_LABELS[condition.operator] ?? condition.operator

      if (condition.conditionField === CONDITION_FIELD_CUSTOM_FIELD) {
        const field = condition.incidentFieldDefinitionId ? fieldMap.get(condition.incidentFieldDefinitionId) : undefined
        const valueMap = new Map(
          field ? valueOptions(field).map((option) => [option.id, option.name]) : [],
        )
        const names = condition.values.map((value) => valueMap.get(value) ?? value).join(", ")
        return `${field?.name ?? "Custom field"} ${operatorLabel} ${names}`
      }

      const map = condition.conditionField === CONDITION_FIELD_SEVERITY ? severityMap : typeMap
      const fieldLabel = FIELD_LABELS[condition.conditionField as FixedConditionField] ?? condition.conditionField
      const names = condition.values.map((value) => map.get(value) ?? value).join(", ")
      return `${fieldLabel} ${operatorLabel} ${names}`
    })
    .join(" AND ")
}

// What the Conditions column says. A runbook with neither conditions nor the
// always flag never attaches on its own, and saying so beats an empty cell.
export function attachSummary(
  runbook: { conditions?: IncidentConditionSettings[] | null; alwaysAttach: boolean },
  incidentTypes: IncidentTypeSettings[],
  severities: IncidentSeveritySettings[],
  customFields: RunbookCustomField[],
): string {
  const summary = conditionSummary(runbook.conditions ?? [], incidentTypes, severities, customFields)
  if (summary) {
    return summary
  }
  return runbook.alwaysAttach ? "Every incident" : "Attach by hand"
}

export function valueOptions(field: RunbookCustomField): { id: string; name: string }[] {
  if (field.entries.length > 0) {
    return field.entries.map((entry) => ({ id: entry.id, name: entry.name }))
  }
  return field.options.map((option) => ({ id: option.id, name: option.name }))
}
