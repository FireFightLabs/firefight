import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

const apiResources = [
  { key: "incidents", label: "Incidents" },
  { key: "severities", label: "Severities" },
  { key: "statuses", label: "Statuses" },
  { key: "incident_types", label: "Incident Types" },
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
