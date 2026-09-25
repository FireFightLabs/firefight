import { Link } from "@inertiajs/react"

import { Button } from "@/components/ui/button"

// Newer and Older buttons. The server only says whether there are more rows, since counting across all workspaces is
// slow.
export function Pager({ page, more, hrefFor }: { page: number; more: boolean; hrefFor: (page: number) => string }) {
  if (page === 1 && !more) {
    return null
  }

  return (
    <div className="flex items-center justify-end gap-3 px-4 py-3 text-sm text-muted-foreground">
      <span>Page {page}</span>
      <Button asChild variant="outline" size="sm" disabled={page === 1}>
        {page === 1 ? <span>Newer</span> : <Link href={hrefFor(page - 1)}>Newer</Link>}
      </Button>
      <Button asChild variant="outline" size="sm" disabled={!more}>
        {more ? <Link href={hrefFor(page + 1)}>Older</Link> : <span>Older</span>}
      </Button>
    </div>
  )
}
