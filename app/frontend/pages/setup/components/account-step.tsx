import { usePage } from "@inertiajs/react"
import { IconCircleCheck } from "@tabler/icons-react"

import type { SetupPageProps } from "@/pages/setup/types"

// Signing in made the account, so this step is done before setup opens.
export function AccountStep() {
  const { email, workspaceName } = usePage<SetupPageProps>().props

  return (
    <div className="border-border flex items-start gap-3 rounded-lg border p-4">
      <IconCircleCheck className="mt-0.5 size-5 shrink-0 text-brand" />
      <p className="text-sm leading-relaxed text-fg-body">
        You are signed in as <span className="font-medium text-fg-primary">{email}</span>, an admin of {workspaceName}.
        The steps after this one get Halon ready to work on your stack.
      </p>
    </div>
  )
}
