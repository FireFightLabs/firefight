import { IconAlertCircle, IconDownload, IconFileText } from "@tabler/icons-react"

import { CHAT_ATTACHMENT_KINDS } from "@/lib/generated/constants"
import type { AgentChatAttachment } from "@/types/serializers"

interface MessageAttachmentsProps {
  attachments: AgentChatAttachment[]
  onOpenImage: (attachmentId: string) => void
}

// The files on a person's message: images inline, opening full size, and every other file as a chip that downloads it.
// The thread holds the full size view, so it stays open when the server's message replaces the one shown on sending.
export function MessageAttachments({ attachments, onOpenImage }: MessageAttachmentsProps) {
  const images = attachments.filter((attachment) => attachment.kind === CHAT_ATTACHMENT_KINDS.IMAGE)
  const files = attachments.filter((attachment) => attachment.kind !== CHAT_ATTACHMENT_KINDS.IMAGE)

  return (
    <div className="flex max-w-[85%] flex-col items-end gap-1.5 self-end sm:max-w-[75%]">
      {images.length > 0 && (
        <div className="flex flex-wrap justify-end gap-1.5">
          {images.map((image) => (
            <button
              key={image.id}
              type="button"
              onClick={() => onOpenImage(image.id)}
              aria-label={`Open ${image.name}`}
              className="overflow-hidden rounded-[12px] border border-border transition-opacity duration-150 hover:opacity-90"
            >
              <img src={image.url} alt={image.name} className="max-h-48 max-w-64 object-cover" />
            </button>
          ))}
        </div>
      )}
      {files.map((file) => (
        <FileChip key={file.id} file={file} />
      ))}
    </div>
  )
}

const CHIP_CLASS = "flex max-w-full items-center gap-2 rounded-[12px] border border-border bg-surface px-3 py-2 text-[13px]"

// A file Halon did not read has nothing to download, and says why.
function FileChip({ file }: { file: AgentChatAttachment }) {
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
