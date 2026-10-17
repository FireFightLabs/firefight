import type { ReactNode } from "react"

import { csrfToken } from "@/lib/http"

interface AuthPostFormProps {
  action: string
  className?: string
  onSubmit?: () => void
  children: ReactNode
}

// A sign-in or an install starts only from a form posted with Firefight's token, never from a link, so a page elsewhere
// cannot start one in someone's browser.
export function AuthPostForm({ action, className, onSubmit, children }: AuthPostFormProps) {
  return (
    <form action={action} method="post" className={className} onSubmit={onSubmit}>
      <input type="hidden" name="authenticity_token" value={csrfToken()} />
      {children}
    </form>
  )
}
