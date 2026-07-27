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

export function RowActions({
  onEdit,
  onDelete,
  deleteDisabledReason,
}: {
  onEdit: () => void
  onDelete: () => void
  // When set, Delete stays visible but inert, and this explains why on hover.
  deleteDisabledReason?: string
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
          <IconDotsVertical className="size-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-32">
        <DropdownMenuItem onClick={onEdit}>Edit</DropdownMenuItem>
        <DropdownMenuSeparator />
        {deleteDisabledReason ? (
          <Tooltip>
            <TooltipTrigger asChild>
              {/* A disabled menu item swallows pointer events, so the span carries the hover. */}
              <span className="block">
                <DropdownMenuItem
                  variant="destructive"
                  disabled
                  onSelect={(e) => e.preventDefault()}
                >
                  Delete
                </DropdownMenuItem>
              </span>
            </TooltipTrigger>
            <TooltipContent side="left" className="max-w-56">
              {deleteDisabledReason}
            </TooltipContent>
          </Tooltip>
        ) : (
          <DropdownMenuItem variant="destructive" onClick={onDelete}>Delete</DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
