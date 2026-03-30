import { IconChevronDown, IconLayoutColumns } from "@tabler/icons-react"
import { type Table } from "@tanstack/react-table"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

interface ColumnVisibilityDropdownProps<TData> {
  table: Table<TData>
}

export function ColumnVisibilityDropdown<TData>({ table }: ColumnVisibilityDropdownProps<TData>) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          <IconLayoutColumns />
          <span className="hidden lg:inline">Customize Columns</span>
          <span className="lg:hidden">Columns</span>
          <IconChevronDown />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        {table
          .getAllColumns()
          .filter(
            (column) =>
              typeof column.accessorFn !== "undefined" && column.getCanHide()
          )
          .map((column) => (
            <DropdownMenuCheckboxItem
              key={column.id}
              checked={column.getIsVisible()}
              onCheckedChange={(value) => column.toggleVisibility(!!value)}
            >
              {typeof column.columnDef.header === "string" ? column.columnDef.header : column.id}
            </DropdownMenuCheckboxItem>
          ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
