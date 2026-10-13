import { router, usePage } from "@inertiajs/react"
import { IconCheck, IconCopy, IconRefresh } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { postJson } from "@/lib/http"
import { workflowHookReplacePath, workflowHookSecretPath } from "@/lib/routes"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import type { WorkflowPageProps } from "@/pages/halon/lib/workflow/types"

const COPIED_FOR_MS = 1500

type Copied = "url" | "secret"

// Where an inbound webhook starts the workflow, and how a sender signs what it posts, as Firefight's outbound webhooks
// are signed. The secret is fetched only when copied, so it never rides in the page, and only someone who may change
// the workflow can copy it or replace the address.
export function WebhookAddress() {
  const { workflow } = usePage<WorkflowPageProps>().props
  const { manage } = useWorkflowAccess()
  const [ copied, setCopied ] = useState<Copied | null>(null)
  const [ problem, setProblem ] = useState<string | null>(null)
  const [ replacing, setReplacing ] = useState(false)

  function markCopied(what: Copied) {
    setCopied(what)
    setTimeout(() => setCopied(null), COPIED_FOR_MS)
  }

  async function copyUrl() {
    await navigator.clipboard.writeText(workflow.hookUrl)
    markCopied("url")
  }

  async function copySecret() {
    setProblem(null)
    try {
      const { ok, data } = await postJson<{ secret: string }>(workflowHookSecretPath(workflow.id))
      if (!ok || !data) {
        setProblem("The secret could not be read. Try again.")
        return
      }
      await navigator.clipboard.writeText(data.secret)
      markCopied("secret")
    } catch {
      setProblem("Firefight could not be reached. Try again.")
    }
  }

  function askReplace() {
    setReplacing(true)
  }

  function cancelReplace() {
    setReplacing(false)
  }

  function replace() {
    setReplacing(false)
    router.post(workflowHookReplacePath(workflow.id), {}, { preserveScroll: true })
  }

  return (
    <section className="space-y-2">
      <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Its address</h4>
      <p data-hook-url className="font-mono text-xs break-all text-fg-body">{workflow.hookUrl}</p>
      <div className="flex flex-wrap gap-1.5">
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={() => void copyUrl()}>
          {copied === "url" ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
          Copy address
        </Button>
        {manage && (
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={() => void copySecret()}>
            {copied === "secret" ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
            Copy secret
          </Button>
        )}
        {manage && (
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={askReplace}>
            <IconRefresh className="size-3.5" />
            Replace address
          </Button>
        )}
      </div>
      {problem && <p className="text-xs text-destructive">{problem}</p>}
      <p className="text-xs text-fg-muted">
        POST a JSON object to it. Sign it as Firefight signs its outbound webhooks: send the time in X-Firefight-Timestamp and
        v1= followed by the HMAC-SHA256 of v1:timestamp:body, keyed by the secret, in X-Firefight-Signature. A delivery more than
        five minutes old is refused. Send an id in X-Firefight-Delivery and a delivery sent again starts nothing new.
      </p>
      <p className="text-xs text-fg-muted">Steps read what it was sent as {"{{trigger.body}}"}, and conditions as body.field, such as body.service.</p>
      <ConfirmDeleteDialog
        open={replacing}
        title={`Replace the webhook address of ${workflow.name}?`}
        description="The old address and its secret stop starting the workflow at once. Give whatever sends to it the new address and secret."
        confirmLabel="Replace address"
        onConfirm={replace}
        onCancel={cancelReplace}
      />
    </section>
  )
}
