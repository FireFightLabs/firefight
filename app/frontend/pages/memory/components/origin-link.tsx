import { Link } from "@inertiajs/react"
import type { ReactNode } from "react"

interface OriginLinkProps {
  url: string | null | undefined
  // A pull request on its code host opens in a new tab, an incident in the dashboard opens in place.
  elsewhere: boolean
  className?: string
  children: ReactNode
}

// Where a lesson came from: an incident's page, or the pull request Halon opened. Plain text when there is no address.
export function OriginLink({ url, elsewhere, className, children }: OriginLinkProps) {
  if (!url) {
    return <span>{children}</span>
  }
  if (elsewhere) {
    return (
      <a href={url} target="_blank" rel="noreferrer" className={className}>
        {children}
      </a>
    )
  }
  return (
    <Link href={url} className={className}>
      {children}
    </Link>
  )
}
