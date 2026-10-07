import { router } from "@inertiajs/react"

import { FireFightLogo } from "@/components/fire-fight-logo"
import { Button } from "@/components/ui/button"
import { logoutPath } from "@/lib/routes"

function logOut() {
  router.delete(logoutPath())
}

// Setup has no navigation until it is done, so the only way out is signing out.
export function SetupHeader({ workspaceName, email }: { workspaceName: string; email: string }) {
  return (
    <header className="border-border flex h-14 shrink-0 items-center justify-between gap-4 border-b px-4 md:px-6">
      <div className="flex min-w-0 items-center gap-2.5">
        <FireFightLogo className="size-5 shrink-0" />
        <span className="truncate text-sm font-medium text-fg-headline">{workspaceName}</span>
      </div>
      <div className="flex min-w-0 items-center gap-3">
        <span className="hidden truncate text-xs text-fg-muted sm:inline">{email}</span>
        <Button variant="ghost" size="sm" onClick={logOut}>
          Log out
        </Button>
      </div>
    </header>
  )
}
