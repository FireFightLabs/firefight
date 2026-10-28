import { router } from "@inertiajs/react"

import { Blocked } from "@/components/blocked-tooltip"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { checkAiAccountPath, subscriptionSignInsPath } from "@/lib/routes"
import { AI_ACCOUNT_STATES } from "@/lib/generated/constants"
import { SubscriptionLimit } from "@/components/ai/subscription-limit"
import type { WorkspaceAiAccount } from "@/types/serializers"

const WORDS: Record<WorkspaceAiAccount["state"], string> = {
  verified: "Works",
  unchecked: "Not checked",
  out_of_credit: "Out of credit",
  failing: "Key refused",
  signed_out: "Sign-in stopped working",
  limit_reached: "Limit reached",
  disabled: "Off",
}

const VARIANTS: Record<WorkspaceAiAccount["state"], "secondary" | "destructive" | "outline"> = {
  verified: "secondary",
  unchecked: "outline",
  out_of_credit: "destructive",
  failing: "destructive",
  signed_out: "destructive",
  limit_reached: "outline",
  disabled: "outline",
}

const EXPLAINED: WorkspaceAiAccount["state"][] = [ AI_ACCOUNT_STATES.OUT_OF_CREDIT, AI_ACCOUNT_STATES.FAILING, AI_ACCOUNT_STATES.UNCHECKED ]

// What Halon makes of the account, why when it is skipping it, and a way to check it again once it is fixed. A
// subscription also says how much of its limit is left, and one whose sign-in stopped working is signed in again.
export function AiAccountState({ account, readOnly }: { account: WorkspaceAiAccount; readOnly: boolean }) {
  const signedOut = account.state === AI_ACCOUNT_STATES.SIGNED_OUT
  const recheckable = !readOnly && account.enabled && !signedOut && account.state !== AI_ACCOUNT_STATES.VERIFIED
  const explained = EXPLAINED.includes(account.state)
  const blocked = account.editBlockedReason ?? undefined

  function check() {
    router.post(checkAiAccountPath(account.id), {}, { preserveScroll: true })
  }

  function signInAgain() {
    router.post(subscriptionSignInsPath(), { account_id: account.id }, { preserveScroll: true })
  }

  return (
    <div className="flex flex-col items-start gap-1">
      <Badge variant={VARIANTS[account.state]}>{WORDS[account.state]}</Badge>
      {account.subscription && <SubscriptionLimit subscription={account.subscription} />}
      {signedOut && (
        <p className="max-w-64 text-xs text-muted-foreground">Halon cannot use it until someone signs in to it again.</p>
      )}
      {explained && account.lastError && <p className="max-w-64 text-xs text-muted-foreground">{account.lastError}</p>}
      {!readOnly && signedOut && (
        <Blocked reason={blocked}>
          <Button variant="link" size="sm" className="h-auto p-0 text-xs" disabled={Boolean(blocked)} onClick={signInAgain}>
            Reconnect
          </Button>
        </Blocked>
      )}
      {recheckable && (
        <Blocked reason={blocked}>
          <Button variant="link" size="sm" className="h-auto p-0 text-xs" disabled={Boolean(blocked)} onClick={check}>
            Check again
          </Button>
        </Blocked>
      )}
    </div>
  )
}
