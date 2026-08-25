import type IncidentConditionSettings from "@/types/IncidentConditionSettings"
import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
} from "@/types/serializers"
import { CONDITION_FIELD_LABELS, CONDITION_OPERATOR_LABELS } from "@/lib/generated/constants"

export const CONDITION_FIELD_INCIDENT_TYPE = "incident_type"
export const CONDITION_FIELD_SEVERITY = "severity"
export const CONDITION_FIELD_CUSTOM_FIELD = "custom_field"
export const OPERATOR_ONE_OF = "one_of"
export const OPERATOR_NOT_ONE_OF = "not_one_of"

const fieldLabels: Record<string, string> = CONDITION_FIELD_LABELS
const operatorLabels: Record<string, string> = CONDITION_OPERATOR_LABELS

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
      const operatorLabel = operatorLabels[condition.operator] ?? condition.operator

      if (condition.conditionField === CONDITION_FIELD_CUSTOM_FIELD) {
        const field = condition.incidentFieldDefinitionId ? fieldMap.get(condition.incidentFieldDefinitionId) : undefined
        const valueMap = new Map(
          field ? valueOptions(field).map((option) => [option.id, option.name]) : [],
        )
        const names = condition.values.map((value) => valueMap.get(value) ?? value).join(", ")
        return `${field?.name ?? "Custom field"} ${operatorLabel} ${names}`
      }

      const map = condition.conditionField === CONDITION_FIELD_SEVERITY ? severityMap : typeMap
      const fieldLabel = fieldLabels[condition.conditionField] ?? condition.conditionField
      const names = condition.values.map((value) => map.get(value) ?? value).join(", ")
      return `${fieldLabel} ${operatorLabel} ${names}`
    })
    .join(" AND ")
}

// What the Conditions column says. The server decides how a runbook reaches
// incidents, and attachMode comes from the same rule automatic attachment
// uses. This only renders it. A runbook that never attaches on its own says
// so, which beats an empty cell.
export function attachSummary(
  runbook: { conditions?: IncidentConditionSettings[] | null; attachMode: "always" | "conditional" | "manual" },
  incidentTypes: IncidentTypeSettings[],
  severities: IncidentSeveritySettings[],
  customFields: RunbookCustomField[],
): string {
  if (runbook.attachMode === "conditional") {
    const summary = conditionSummary(runbook.conditions ?? [], incidentTypes, severities, customFields)
    if (summary) {
      return summary
    }
  }
  return runbook.attachMode === "always" ? "Every incident" : "Attach by hand"
}

export function valueOptions(field: RunbookCustomField): { id: string; name: string }[] {
  if (field.entries.length > 0) {
    return field.entries.map((entry) => ({ id: entry.id, name: entry.name }))
  }
  return field.options.map((option) => ({ id: option.id, name: option.name }))
}
