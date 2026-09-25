import { Link } from "@inertiajs/react"

import { Button } from "@/components/ui/button"

// Newest first, a page at a time. Only "is there more" is known, since counting every row across workspaces is not worth it.
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
