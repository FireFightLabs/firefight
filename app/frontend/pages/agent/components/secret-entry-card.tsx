import { IconKey } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { SECRET_ENTRY_KINDS } from "@/lib/generated/constants"
import { EnterValueDialog } from "@/pages/agent/components/enter-value-dialog"
import { RevealDialog } from "@/pages/agent/components/reveal-dialog"
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
