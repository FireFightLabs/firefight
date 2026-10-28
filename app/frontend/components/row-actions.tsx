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
  editDisabledReason,
  deleteDisabledReason,
  deleteLabel = "Delete",
}: {
  onEdit?: () => void
  onDelete: () => void
  editDisabledReason?: string | null
  deleteDisabledReason?: string
  // What taking the row away is called, such as Remove for a member, whose row stays in the history.
  deleteLabel?: string
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
        {onEdit && editDisabledReason && (
          <>
            <Tooltip>
              <TooltipTrigger asChild>
                <span className="block">
                  <DropdownMenuItem disabled onSelect={(event) => event.preventDefault()}>Edit</DropdownMenuItem>
                </span>
              </TooltipTrigger>
              <TooltipContent side="left" className="max-w-56">{editDisabledReason}</TooltipContent>
            </Tooltip>
            <DropdownMenuSeparator />
          </>
        )}
        {onEdit && !editDisabledReason && (
          <>
            <DropdownMenuItem onClick={onEdit}>Edit</DropdownMenuItem>
            <DropdownMenuSeparator />
          </>
        )}
        {deleteDisabledReason ? (
          <Tooltip>
            <TooltipTrigger asChild>
              {/* A disabled menu item swallows pointer events, so the span carries the hover. */}
              <span className="block">
                <DropdownMenuItem
                  variant="destructive"
                  disabled
                  onSelect={(event) => event.preventDefault()}
                >
                  {deleteLabel}
                </DropdownMenuItem>
              </span>
            </TooltipTrigger>
            <TooltipContent side="left" className="max-w-56">
              {deleteDisabledReason}
            </TooltipContent>
          </Tooltip>
        ) : (
          <DropdownMenuItem variant="destructive" onClick={onDelete}>{deleteLabel}</DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
