import { Link, usePage } from "@inertiajs/react"

import { operatorHalonChatsPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Trace } from "@/pages/operator/components/trace"
import { dollars } from "@/pages/operator/lib/format"
import { TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonChat, OperatorTraceGroup } from "@/types/serializers"

interface ChatProps extends OperatorPageProps {
  chat: OperatorHalonChat
  turns: number
  groups: OperatorTraceGroup[]
}

function turnsLabel(shown: number, turns: number): string {
  if (shown < turns) {
    return `latest ${shown} of ${turns} turns`
  }
  return turns === 1 ? "1 turn" : `${turns} turns`
}

export default function OperatorHalonChat() {
  const { chat, turns, groups } = usePage<ChatProps>().props

  return (
    <OperatorLayout title={chat.title}>
      <Link href={operatorHalonChatsPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All chats
      </Link>
      <PageHeading
        title={chat.title}
        lead="Each turn on its own clock: what the person asked, every model call and tool call that followed, the reply, and any run it started. Select a span to read it."
      />
      <div className="mb-6 flex flex-wrap items-center gap-2 text-xs">
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>{chat.workspaceName}</span>
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>{chat.kind}</span>
        {chat.incidentLabel && <span className={`rounded-full border px-2.5 py-1 font-mono ${TONE_CLASSES.neutral}`}>{chat.incidentLabel}</span>}
        <span className={`rounded-full border px-2.5 py-1 font-mono ${TONE_CLASSES.neutral}`}>{dollars(chat.spentMicros)}</span>
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>
          {turnsLabel(groups.length, turns)}
        </span>
      </div>
      <Trace groups={groups} />
    </OperatorLayout>
  )
}
