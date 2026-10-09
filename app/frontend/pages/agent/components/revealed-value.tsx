import { IconClipboard, IconKey, IconLoader2 } from "@tabler/icons-react"
import { useEffect, useState } from "react"

import { Button } from "@/components/ui/button"
import { DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { postJson } from "@/lib/http"
import { agentChatSecretEntryRevealPath } from "@/lib/routes"
import type { SecretDialogProps } from "@/pages/agent/types"

interface RevealAnswer {
  value?: string
  error?: string
}

// Mounted only while open, so the value is read again each time and gone once the dialog closes.
export function RevealedValue({ conversationId, entry, onClose }: Omit<SecretDialogProps, "open">) {
  const [ value, setValue ] = useState<string | null>(null)
  const [ problem, setProblem ] = useState<string | null>(null)
  const [ copied, setCopied ] = useState(false)

  useEffect(() => {
    let current = true
    function shown(answer: { ok: boolean; data: RevealAnswer | null }) {
      if (!current) {
        return
      }
      if (answer.ok && answer.data?.value) {
        setValue(answer.data.value)
      } else {
        setProblem(answer.data?.error ?? "It could not be read. Try again.")
      }
    }

    function failed() {
      if (current) {
        setProblem("Firefight could not be reached. Try again.")
      }
    }

    postJson<RevealAnswer>(agentChatSecretEntryRevealPath(conversationId, entry.id)).then(shown, failed)
    return () => {
      current = false
    }
  }, [ conversationId, entry.id ])

  function copy() {
    if (value === null) {
      return
    }

    void navigator.clipboard.writeText(value).then(markCopied)
  }

  function markCopied() {
    setCopied(true)
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <IconKey className="size-5 text-brand" />
          {entry.headline}
        </DialogTitle>
        <DialogDescription>{entry.body}</DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-3 py-2">
        {value !== null && (
          <div className="flex items-center gap-2">
            <code className="flex-1 rounded-md bg-muted px-3 py-2 font-mono text-sm break-all">{value}</code>
            <Button variant="outline" size="sm" onClick={copy}>
              <IconClipboard className="size-4" />
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
        )}
        {value === null && problem === null && (
          <p className="flex items-center gap-2 text-sm text-fg-secondary">
            <IconLoader2 className="size-4 motion-safe:animate-spin" />
            Reading it now
          </p>
        )}
        {problem !== null && <p className="text-sm text-fg-secondary">{problem}</p>}
      </div>
      <DialogFooter>
        <Button onClick={onClose}>Done</Button>
      </DialogFooter>
    </>
  )
}
