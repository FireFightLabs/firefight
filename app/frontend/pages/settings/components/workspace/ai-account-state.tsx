import { router } from "@inertiajs/react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { checkAiAccountPath } from "@/lib/routes"
import type { WorkspaceAiAccount } from "@/types/serializers"

const WORDS: Record<WorkspaceAiAccount["state"], string> = {
  verified: "Works",
  unchecked: "Not checked",
  out_of_credit: "Out of credit",
  failing: "Key refused",
  disabled: "Off",
}

const VARIANTS: Record<WorkspaceAiAccount["state"], "secondary" | "destructive" | "outline"> = {
  verified: "secondary",
  unchecked: "outline",
  out_of_credit: "destructive",
  failing: "destructive",
  disabled: "outline",
}

// What Halon makes of the account, why when it is skipping it, and a way to check it again once it is fixed.
export function AiAccountState({ account, readOnly }: { account: WorkspaceAiAccount; readOnly: boolean }) {
  const recheckable = !readOnly && account.enabled && account.state !== "verified"
  const explained = account.state === "out_of_credit" || account.state === "failing" || account.state === "unchecked"

  function check() {
    router.post(checkAiAccountPath(account.id), {}, { preserveScroll: true })
  }

  return (
    <div className="flex flex-col items-start gap-1">
      <Badge variant={VARIANTS[account.state]}>{WORDS[account.state]}</Badge>
      {explained && account.lastError && <p className="max-w-64 text-xs text-muted-foreground">{account.lastError}</p>}
      {recheckable && (
        <Button variant="link" size="sm" className="h-auto p-0 text-xs" onClick={check}>
          Check again
        </Button>
      )}
    </div>
  )
}
