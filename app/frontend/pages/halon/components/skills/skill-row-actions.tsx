import { IconDotsVertical } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { exportHalonSkillPath } from "@/lib/routes"
import type { HalonSkill } from "@/types/serializers"

interface SkillRowActionsProps {
  skill: HalonSkill
  canManage: boolean
  onEdit: () => void
  onHistory: () => void
  onLibraryUpdate: () => void
  onDelete: () => void
}

// The row menu of the shared option lists, with a skill's history, its SKILL.md file and Firefight's newer version
// beside Edit and Delete. Delete stays visible but inert while a workflow runs the skill, with why.
export function SkillRowActions({ skill, canManage, onEdit, onHistory, onLibraryUpdate, onDelete }: SkillRowActionsProps) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
          <IconDotsVertical className="size-4" />
          <span className="sr-only">Actions for {skill.name}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        {canManage && <DropdownMenuItem onClick={onEdit}>Edit</DropdownMenuItem>}
        <DropdownMenuItem onClick={onHistory}>History</DropdownMenuItem>
        {skill.libraryUpdate && (
          <DropdownMenuItem onClick={onLibraryUpdate}>See Firefight&apos;s version {skill.libraryUpdate.version}</DropdownMenuItem>
        )}
        <DropdownMenuItem asChild>
          <a href={exportHalonSkillPath(skill.id)} download>Export SKILL.md</a>
        </DropdownMenuItem>
        {canManage && (
          <>
            <DropdownMenuSeparator />
            {skill.deletionBlockedReason ? (
              <Tooltip>
                <TooltipTrigger asChild>
                  {/* A disabled menu item swallows pointer events, so the span carries the hover. */}
                  <span className="block">
                    <DropdownMenuItem variant="destructive" disabled onSelect={(event) => event.preventDefault()}>
                      Delete
                    </DropdownMenuItem>
                  </span>
                </TooltipTrigger>
                <TooltipContent side="left" className="max-w-56">{skill.deletionBlockedReason}</TooltipContent>
              </Tooltip>
            ) : (
              <DropdownMenuItem variant="destructive" onClick={onDelete}>Delete</DropdownMenuItem>
            )}
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
