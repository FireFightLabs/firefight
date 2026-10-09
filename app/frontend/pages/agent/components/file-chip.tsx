import { IconAlertCircle, IconDownload, IconFileText } from "@tabler/icons-react"

import { CHAT_ATTACHMENT_KINDS } from "@/lib/generated/constants"
import type { AgentChatAttachment } from "@/types/serializers"

const CHIP_CLASS = "flex max-w-full items-center gap-2 rounded-[12px] border border-border bg-surface px-3 py-2 text-[13px]"

// A file Halon did not read has nothing to download, and says why.
export function FileChip({ file }: { file: AgentChatAttachment }) {
  if (file.kind === CHAT_ATTACHMENT_KINDS.UNREAD) {
    return (
      <div className={CHIP_CLASS} title={file.unreadReason ?? undefined}>
        <IconAlertCircle className="size-4 shrink-0 text-ink-3" />
        <span className="truncate text-ink">{file.name}</span>
        <span className="shrink-0 text-ink-3">Not read</span>
      </div>
    )
  }

  return (
    <a href={file.url} download={file.name} className={`${CHIP_CLASS} transition-colors duration-100 hover:bg-hover`}>
      <IconFileText className="size-4 shrink-0 text-ink-3" />
      <span className="truncate text-ink">{file.name}</span>
      <span className="shrink-0 text-ink-3">{file.size}</span>
      <IconDownload className="size-4 shrink-0 text-ink-3" />
    </a>
  )
}
