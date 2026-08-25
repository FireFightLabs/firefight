import type { MouseEvent } from "react"
import { flexRender, type Row, type Table as TanStackTable } from "@tanstack/react-table"

import { Card, CardContent } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

interface DataTableProps<TData> {
  table: TanStackTable<TData>
  emptyMessage?: string
  onRowClick?: (record: TData) => void
}

// A row that navigates still holds real links, so a click that landed on one
// is left to the link and never fires the row twice.
function rowClickHandler<TData>(row: Row<TData>, onRowClick?: (record: TData) => void) {
  if (!onRowClick) {
    return undefined
  }
  return (event: MouseEvent<HTMLTableRowElement>) => {
    if ((event.target as HTMLElement).closest("a, button")) {
      return
    }
    onRowClick(row.original)
  }
}

export function DataTable<TData>({ table, emptyMessage = "No results found.", onRowClick }: DataTableProps<TData>) {
  const rowClassName = onRowClick ? "cursor-pointer" : undefined
  return (
    <Card className="overflow-hidden py-0">
      <CardContent className="p-0">
        <Table>
          <TableHeader className="sticky top-0 z-10 bg-card">
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id} colSpan={header.colSpan}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(header.column.columnDef.header, header.getContext())}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows?.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow key={row.id} className={rowClassName} onClick={rowClickHandler(row, onRowClick)}>
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id} className="py-4">
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={table.getAllColumns().length}
                  className="h-24 text-center"
                >
                  {emptyMessage}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
