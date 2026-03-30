import {
  IconChevronLeft,
  IconChevronRight,
  IconChevronsLeft,
  IconChevronsRight,
} from "@tabler/icons-react"

import type { Pagination } from "@/types"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

const DEFAULT_PAGE_SIZE_OPTIONS = [10, 20, 30, 40, 50]

interface TablePaginationProps {
  pagination: Pagination
  onPageChange: (page: number) => void
  onPerPageChange: (perPage: number) => void
  totalLabel?: string
  pageSizeOptions?: number[]
}

export function TablePagination({
  pagination,
  onPageChange,
  onPerPageChange,
  totalLabel = "row(s) total",
  pageSizeOptions = DEFAULT_PAGE_SIZE_OPTIONS,
}: TablePaginationProps) {
  const { page, perPage, totalCount, totalPages } = pagination
  const canPreviousPage = page > 1
  const canNextPage = page < totalPages

  return (
    <div className="flex items-center justify-between px-4 lg:px-6">
      <div className="hidden flex-1 text-sm text-muted-foreground lg:flex">
        {totalCount} {totalLabel}
      </div>
      <div className="flex w-full items-center gap-8 lg:w-fit">
        <div className="hidden items-center gap-2 lg:flex">
          <Label htmlFor="rows-per-page" className="text-sm font-medium">
            Rows per page
          </Label>
          <Select
            value={`${perPage}`}
            onValueChange={(value) => onPerPageChange(Number(value))}
          >
            <SelectTrigger size="sm" className="w-20" id="rows-per-page">
              <SelectValue placeholder={perPage} />
            </SelectTrigger>
            <SelectContent side="top">
              {pageSizeOptions.map((size) => (
                <SelectItem key={size} value={`${size}`}>
                  {size}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="flex w-fit items-center justify-center text-sm font-medium">
          Page {page} of {totalPages}
        </div>
        <div className="ml-auto flex items-center gap-2 lg:ml-0">
          <Button
            variant="outline"
            className="hidden size-8 lg:flex"
            size="icon"
            onClick={() => onPageChange(1)}
            disabled={!canPreviousPage}
          >
            <span className="sr-only">Go to first page</span>
            <IconChevronsLeft />
          </Button>
          <Button
            variant="outline"
            className="size-8"
            size="icon"
            onClick={() => onPageChange(page - 1)}
            disabled={!canPreviousPage}
          >
            <span className="sr-only">Go to previous page</span>
            <IconChevronLeft />
          </Button>
          <Button
            variant="outline"
            className="size-8"
            size="icon"
            onClick={() => onPageChange(page + 1)}
            disabled={!canNextPage}
          >
            <span className="sr-only">Go to next page</span>
            <IconChevronRight />
          </Button>
          <Button
            variant="outline"
            className="hidden size-8 lg:flex"
            size="icon"
            onClick={() => onPageChange(totalPages)}
            disabled={!canNextPage}
          >
            <span className="sr-only">Go to last page</span>
            <IconChevronsRight />
          </Button>
        </div>
      </div>
    </div>
  )
}
