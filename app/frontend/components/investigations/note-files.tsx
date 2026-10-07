import { useState } from "react"
import { IconAlertCircle, IconDownload, IconFileText, IconPhoto } from "@tabler/icons-react"

import { ImageDialog, type ShownImage } from "@/components/image-dialog"
import { CHAT_ATTACHMENT_KINDS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import type { InvestigationNoteFile } from "@/types/serializers"

const CHIP_CLASS = "flex max-w-full items-center gap-1.5 rounded-md border border-border px-2 py-1 text-xs"
const OPENABLE_CHIP_CLASS = `${CHIP_CLASS} transition-colors duration-100 hover:bg-surface-hover`

// The files that went with a note, by name. An image opens full size and any other file downloads, as in a chat. A
// file Halon did not read was never kept, so it says so, and why on hover.
export function NoteFiles({ files }: { files: InvestigationNoteFile[] }) {
  const [openImage, setOpenImage] = useState<ShownImage | null>(null)

  function closeImage() {
    setOpenImage(null)
  }

  if (files.length === 0) {
    return null
  }

  return (
    <>
      <ul className="flex flex-wrap gap-1.5" aria-label="Files added">
        {files.map((file) => (
          <li key={file.id} className="min-w-0 max-w-full">
            <NoteFile file={file} onOpenImage={setOpenImage} />
          </li>
        ))}
      </ul>
      <ImageDialog image={openImage} onOpenChange={whenClosed(closeImage)} />
    </>
  )
}

function NoteFile({ file, onOpenImage }: { file: InvestigationNoteFile; onOpenImage: (image: ShownImage) => void }) {
  if (file.kind === CHAT_ATTACHMENT_KINDS.UNREAD || !file.url) {
    return (
      <span className={CHIP_CLASS} title={file.unreadReason ?? undefined}>
        <IconAlertCircle className="size-3.5 shrink-0 text-fg-muted" />
        <span className="truncate text-fg-body">{file.name}</span>
        <span className="shrink-0 text-fg-muted">Not read</span>
      </span>
    )
  }

  const url = file.url
  if (file.kind === CHAT_ATTACHMENT_KINDS.IMAGE) {
    return (
      <button
        type="button"
        className={OPENABLE_CHIP_CLASS}
        onClick={() => onOpenImage({ name: file.name, url })}
        aria-label={`Open ${file.name}`}
      >
        <IconPhoto className="size-3.5 shrink-0 text-fg-muted" />
        <span className="truncate text-fg-body">{file.name}</span>
        <span className="shrink-0 text-fg-muted">{file.size}</span>
      </button>
    )
  }

  return (
    <a href={url} download={file.name} className={OPENABLE_CHIP_CLASS} aria-label={`Download ${file.name}`}>
      <IconFileText className="size-3.5 shrink-0 text-fg-muted" />
      <span className="truncate text-fg-body">{file.name}</span>
      <span className="shrink-0 text-fg-muted">{file.size}</span>
      <IconDownload className="size-3.5 shrink-0 text-fg-muted" />
    </a>
  )
}
