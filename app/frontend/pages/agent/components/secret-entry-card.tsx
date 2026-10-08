import { router } from "@inertiajs/react"
import { IconClipboard, IconKey, IconLoader2 } from "@tabler/icons-react"
import { type FormEvent, useEffect, useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { Button as DialogButton } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { SECRET_ENTRY_KINDS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { postJson } from "@/lib/http"
import { agentChatSecretEntryFillPath, agentChatSecretEntryRevealPath } from "@/lib/routes"
import { refreshSecretEntries } from "@/pages/agent/lib/chat-updates"
import type { AgentChatSecretEntry } from "@/types/serializers"

interface SecretEntryCardProps {
  conversationId: string
  entry: AgentChatSecretEntry
}

// A secret a tool call handed to the person who asked. An entry opens a field where they type a value Halon never sees,
// and a reveal shows a credential the tool made, read from the provider each time. The server says who may act and why
// not, so the card decides nothing.
export function SecretEntryCard({ conversationId, entry }: SecretEntryCardProps) {
  const [ open, setOpen ] = useState(false)
  const entering = entry.kind === SECRET_ENTRY_KINDS.ENTER

  function openDialog() {
    setOpen(true)
  }

  function closeDialog() {
    setOpen(false)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label={entry.headline}>
      <div className="flex items-start gap-2">
        <IconKey className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink">{entry.headline}</h3>
          <p className="text-[13px] leading-relaxed text-ink-2">{entry.body}</p>
        </div>
      </div>
      {entry.open ? (
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="primary" disabled={entry.blockedReason != null} onClick={openDialog}>
            {entering ? "Enter value" : "Reveal"}
          </Button>
          <span className="text-[12.5px] text-ink-3">{entry.blockedReason ?? entry.statusLine}</span>
        </div>
      ) : (
        <p className="text-[12.5px] text-ink-3">{entry.statusLine}</p>
      )}
      {entering ? (
        <EnterValueDialog conversationId={conversationId} entry={entry} open={open} onClose={closeDialog} />
      ) : (
        <RevealDialog conversationId={conversationId} entry={entry} open={open} onClose={closeDialog} />
      )}
    </section>
  )
}

interface SecretDialogProps {
  conversationId: string
  entry: AgentChatSecretEntry
  open: boolean
  onClose: () => void
}

function EnterValueDialog({ conversationId, entry, open, onClose }: SecretDialogProps) {
  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-md">
        <EnterValueForm conversationId={conversationId} entry={entry} onClose={onClose} />
      </DialogContent>
    </Dialog>
  )
}

// Mounted only while open, so the value never outlives the dialog.
function EnterValueForm({ conversationId, entry, onClose }: Omit<SecretDialogProps, "open">) {
  const [ value, setValue ] = useState("")
  const [ sending, setSending ] = useState(false)
  const fieldId = `secret-value-${entry.id}`
  const blank = value.length === 0

  function save(event: FormEvent) {
    event.preventDefault()
    if (blank || sending) {
      return
    }

    setSending(true)
    router.post(agentChatSecretEntryFillPath(conversationId, entry.id), { secret_value: value }, {
      preserveScroll: true, preserveState: true, onSuccess: settled, onFinish: stopSending,
    })
  }

  function settled() {
    setValue("")
    refreshSecretEntries()
    onClose()
  }

  function stopSending() {
    setSending(false)
  }

  return (
    <form onSubmit={save}>
      <DialogHeader>
        <DialogTitle>{entry.headline}</DialogTitle>
        <DialogDescription>{entry.body}</DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-2 py-4">
        <Label htmlFor={fieldId}>Value</Label>
        <Input
          id={fieldId}
          type="password"
          autoComplete="off"
          spellCheck={false}
          value={value}
          onChange={(event) => setValue(event.target.value)}
          autoFocus
        />
      </div>
      <DialogFooter>
        <DialogButton type="button" variant="outline" onClick={onClose}>Cancel</DialogButton>
        <DialogButton type="submit" disabled={blank || sending}>
          {sending && <IconLoader2 className="size-4 motion-safe:animate-spin" />}
          Set value
        </DialogButton>
      </DialogFooter>
    </form>
  )
}

function RevealDialog({ conversationId, entry, open, onClose }: SecretDialogProps) {
  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="max-w-lg">
        <RevealedValue conversationId={conversationId} entry={entry} onClose={onClose} />
      </DialogContent>
    </Dialog>
  )
}

interface RevealAnswer {
  value?: string
  error?: string
}

// Mounted only while open, so the value is read again each time and gone once the dialog closes.
function RevealedValue({ conversationId, entry, onClose }: Omit<SecretDialogProps, "open">) {
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
            <DialogButton variant="outline" size="sm" onClick={copy}>
              <IconClipboard className="size-4" />
              {copied ? "Copied" : "Copy"}
            </DialogButton>
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
        <DialogButton onClick={onClose}>Done</DialogButton>
      </DialogFooter>
    </>
  )
}
