import {
  ABILITY_ACTIONS,
  ABILITY_GRANTABLE_RESOURCES,
  ABILITY_RESOURCE_ACTIONS,
  ABILITY_RESOURCE_LABELS,
  SKILLS_RESOURCE,
  WORKFLOWS_RESOURCE,
} from "@/lib/generated/constants"
import { usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

const apiResources = ABILITY_GRANTABLE_RESOURCES.map((key) => ({
  key,
  label: ABILITY_RESOURCE_LABELS[key],
  offered: new Set<string>(ABILITY_RESOURCE_ACTIONS[key]),
}))
const apiActions = ABILITY_ACTIONS

export function PermissionsMatrix({
  perms,
  onToggle,
}: {
  perms: Record<string, Set<string>>
  onToggle: (resource: string, action: string) => void
}) {
  const { workflowsEnabled, customSkillsEnabled } = usePage<SharedProps>().props
  // Workflows and the workspace's own skills are offered only where the workspace has them.
  const hidden: string[] = [ ...(workflowsEnabled ? [] : [ WORKFLOWS_RESOURCE ]), ...(customSkillsEnabled ? [] : [ SKILLS_RESOURCE ]) ]
  const resources = apiResources.filter((resource) => !hidden.includes(resource.key))

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
          {resources.map((resource) => (
            <TableRow key={resource.key}>
              <TableCell className="font-medium">{resource.label}</TableCell>
              {apiActions.map((action) => (
                <TableCell key={action} className="text-center">
                  {resource.offered.has(action) ? (
                    <Switch
                      checked={perms[resource.key]?.has(action) ?? false}
                      onCheckedChange={() => onToggle(resource.key, action)}
                    />
                  ) : (
                    <span className="text-muted-foreground" aria-label={`${resource.label} has no ${action}`}>-</span>
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
