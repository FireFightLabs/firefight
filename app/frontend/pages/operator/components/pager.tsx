import { Link } from "@inertiajs/react"

import { Button } from "@/components/ui/button"

// Newer and Older buttons, or the labels a list in another order passes. The server only says whether there are more
// rows, since counting across all workspaces is slow.
export function Pager({
  page,
  more,
  hrefFor,
  labels = ["Newer", "Older"],
}: {
  page: number
  more: boolean
  hrefFor: (page: number) => string
  labels?: [string, string]
}) {
  if (page === 1 && !more) {
    return null
  }

  return (
    <div className="flex items-center justify-end gap-3 px-4 py-3 text-sm text-muted-foreground">
      <span>Page {page}</span>
      <Button asChild variant="outline" size="sm" disabled={page === 1}>
        {page === 1 ? <span>{labels[0]}</span> : <Link href={hrefFor(page - 1)}>{labels[0]}</Link>}
      </Button>
      <Button asChild variant="outline" size="sm" disabled={!more}>
        {more ? <Link href={hrefFor(page + 1)}>{labels[1]}</Link> : <span>{labels[1]}</span>}
      </Button>
    </div>
  )
}
