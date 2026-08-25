import { WEBHOOK_EVENTS, type WebhookEvent } from "@/lib/generated/constants"

const EVENT_LABELS: Record<WebhookEvent, string> = {
  "incident.created": "Incident created",
  "incident.updated": "Incident updated",
  "incident.accepted": "Incident accepted",
  "incident.resolved": "Incident resolved",
  "incident.reopened": "Incident reopened",
  "incident.canceled": "Incident canceled",
  "incident.escalated": "Incident escalated",
  "lead.assigned": "Lead assigned",
  "role.assigned": "Role assigned",
  "role.unassigned": "Role unassigned",
  "action.created": "Action created",
  "action.picked_up": "Action picked up",
  "action.completed": "Action completed",
  "action.reassigned": "Action reassigned",
  "runbook.attached": "Runbook attached",
  "postmortem.generated": "Postmortem generated",
  "postmortem.edited": "Postmortem edited",
  "relationship.created": "Relationship created",
  "incident.marked_duplicate": "Incident marked duplicate",
  "incident.merged_into": "Incident merged into",
}

export const subscribableEvents = WEBHOOK_EVENTS.map((value) => ({ value, label: EVENT_LABELS[value] }))

export const eventLabel = (value: string) =>
  subscribableEvents.find((event) => event.value === value)?.label ?? value
