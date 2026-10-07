import { IconAlertCircle, IconFileText, IconPhoto } from "@tabler/icons-react"

import { CHAT_ATTACHMENT_KINDS } from "@/lib/generated/constants"
import type { InvestigationNoteFile } from "@/types/serializers"

const CHIP_CLASS = "flex max-w-full items-center gap-1.5 rounded-md border border-border px-2 py-1 text-xs"

// The files that went with a note, by name. A file Halon did not read says so, and why on hover.
export function NoteFiles({ files }: { files: InvestigationNoteFile[] }) {
  if (files.length === 0) {
    return null
  }

  return (
    <ul className="flex flex-wrap gap-1.5" aria-label="Files added">
      {files.map((file) => (
        <li key={file.id} className="min-w-0 max-w-full">
          <NoteFile file={file} />
        </li>
      ))}
    </ul>
  )
}

function NoteFile({ file }: { file: InvestigationNoteFile }) {
  if (file.kind === CHAT_ATTACHMENT_KINDS.UNREAD) {
    return (
      <span className={CHIP_CLASS} title={file.unreadReason ?? undefined}>
        <IconAlertCircle className="size-3.5 shrink-0 text-fg-muted" />
        <span className="truncate text-fg-body">{file.name}</span>
        <span className="shrink-0 text-fg-muted">Not read</span>
      </span>
    )
  }

  const Icon = file.kind === CHAT_ATTACHMENT_KINDS.IMAGE ? IconPhoto : IconFileText
  return (
    <span className={CHIP_CLASS}>
      <Icon className="size-3.5 shrink-0 text-fg-muted" />
      <span className="truncate text-fg-body">{file.name}</span>
      <span className="shrink-0 text-fg-muted">{file.size}</span>
    </span>
  )
}
