import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

// `actions` lists only what the API actually supports for each resource, so
// the UI never offers a toggle that maps to no endpoint. Keep in sync with
// ApiKey::RESOURCES + the routes under /api/v1.
const apiResources = [
  { key: "incidents", label: "Incidents", actions: ["read", "create", "update"] },
  { key: "severities", label: "Severities", actions: ["read"] },
  { key: "statuses", label: "Statuses", actions: ["read"] },
  { key: "incident_types", label: "Incident Types", actions: ["read"] },
  { key: "custom_fields", label: "Custom Fields", actions: ["read"] },
  { key: "catalog", label: "Catalogue", actions: ["read", "create", "update", "delete"] },
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
                  {(resource.actions as readonly string[]).includes(action) ? (
                    <Switch
                      checked={perms[resource.key]?.has(action) ?? false}
                      onCheckedChange={() => onToggle(resource.key, action)}
                    />
                  ) : (
                    <span className="text-muted-foreground">—</span>
                  )}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
