import { usePage } from "@inertiajs/react"

import type { SharedProps } from "@/types"

// Mirrors Ability::Action::RESOURCES. The server decides, this only names
// the keys a page may ask about.
export type ManagedResource =
  | "incidents"
  | "severities"
  | "statuses"
  | "incident_types"
  | "custom_fields"
  | "forms"
  | "catalog"
  | "alerts"
  | "policies"
  | "runbooks"
  | "approvals"
  | "incident_roles"
  | "webhooks"
  | "integrations"
  | "api_keys"
  | "permissions"
  | "workspace"

// Whether the signed-in person may change a resource, as the gateway would
// answer. Pages offer controls from this, never from "is admin".
export function useCan(resource: ManagedResource): boolean {
  const { currentUserCan } = usePage<SharedProps>().props
  return Boolean(currentUserCan?.[resource])
}
