import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

// Every resource in Ability::Action::GRANTABLE_RESOURCES, every action in
// Ability::Action::ACTIONS. The admin-only resources (integrations, API keys,
// permissions, workspace) are not here because nothing can be granted them.
const apiResources = [
  { key: "incidents", label: "Incidents" },
  { key: "severities", label: "Severities" },
  { key: "statuses", label: "Statuses" },
  { key: "incident_types", label: "Incident Types" },
  { key: "custom_fields", label: "Custom Fields" },
  { key: "forms", label: "Forms" },
  { key: "catalog", label: "Catalogue" },
  { key: "alerts", label: "Alerts" },
  { key: "policies", label: "Alert Routing" },
  { key: "runbooks", label: "Runbooks" },
  { key: "approvals", label: "Approvals" },
  { key: "incident_roles", label: "Incident Roles" },
  { key: "webhooks", label: "Webhooks" },
] as const

const apiActions = ["read", "create", "update", "delete"] as const

export function PermissionsMatrix({
  perms,
  onToggle,
}: {
  perms: Record<string, Set<string>>
  onToggle: (resource: string, action: string) => void
}) {
  return (
    <div className="rounded-lg border overflow-hidden">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Resource</TableHead>
            {apiActions.map((action) => (
              <TableHead key={action} className="w-16 text-center capitalize">
                {action}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {apiResources.map((resource) => (
            <TableRow key={resource.key}>
              <TableCell className="font-medium">{resource.label}</TableCell>
              {apiActions.map((action) => (
                <TableCell key={action} className="text-center">
                  <Switch
                    checked={perms[resource.key]?.has(action) ?? false}
                    onCheckedChange={() => onToggle(resource.key, action)}
                  />
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
