import { CHAT_ATTACHMENT_KINDS } from "@/lib/generated/constants"
import { FileChip } from "@/pages/agent/components/file-chip"
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
