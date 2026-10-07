import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconMail } from "@tabler/icons-react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { GoogleLogo } from "@/components/auth/google-logo"
import { SlackLogo } from "@/components/auth/slack-logo"
import { Button } from "@/components/ui/button"
import { formatDate } from "@/lib/formatters"
import { SIGN_IN_PROVIDERS } from "@/lib/generated/constants"
import { signInMethodPath } from "@/lib/routes"
import { Blocked } from "@/pages/settings/components/blocked-tooltip"
import type { SignInMethod } from "@/types/serializers"

function ProviderIcon({ provider }: { provider: string }) {
  if (provider === SIGN_IN_PROVIDERS.GOOGLE) {
    return <GoogleLogo className="size-4 shrink-0" />
  }
  if (provider === SIGN_IN_PROVIDERS.SLACK) {
    return <SlackLogo className="size-4 shrink-0" />
  }
  return <IconMail className="size-4 shrink-0 text-muted-foreground" />
}

function usage(method: SignInMethod): string {
  return method.lastUsedAt ? `Last used ${formatDate(method.lastUsedAt)}` : `Added ${formatDate(method.addedAt)}`
}

function describe(method: SignInMethod): string {
  return method.email ? `${method.label} (${method.email})` : method.label
}

export function SignInMethodsList({ methods }: { methods: SignInMethod[] }) {
  const [removing, setRemoving] = useState<SignInMethod | null>(null)

  function cancel() {
    setRemoving(null)
  }

  function confirmRemove() {
    if (!removing) {
      return
    }
    router.delete(signInMethodPath(removing.id), { preserveScroll: true, onFinish: cancel })
  }

  if (methods.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No sign-in methods are recorded yet. The one you use next is added here.
      </p>
    )
  }

  return (
    <>
      <div className="flex flex-col gap-2">
        {methods.map((method) => (
          <div
            key={method.id}
            className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2"
          >
            <div className="flex min-w-0 items-center gap-2.5">
              <ProviderIcon provider={method.provider} />
              <div className="min-w-0">
                <p className="text-sm font-medium">{method.label}</p>
                <p className="truncate text-xs text-muted-foreground">
                  {method.email ? `${method.email} · ` : ""}
                  {usage(method)}
                </p>
              </div>
            </div>
            <Blocked reason={method.removalBlockedReason}>
              <Button
                variant="outline"
                size="sm"
                disabled={Boolean(method.removalBlockedReason)}
                onClick={() => setRemoving(method)}
              >
                Remove
              </Button>
            </Blocked>
          </div>
        ))}
      </div>

      <ConfirmDeleteDialog
        open={removing !== null}
        title={removing ? `Remove ${removing.label}?` : ""}
        description={
          removing
            ? `${describe(removing)} will no longer sign you in. If its email matches your account, signing in with it again adds it back.`
            : ""
        }
        confirmLabel="Remove"
        onConfirm={confirmRemove}
        onCancel={cancel}
      />
    </>
  )
}
