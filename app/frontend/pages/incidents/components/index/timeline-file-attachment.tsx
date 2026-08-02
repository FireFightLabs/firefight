import { useState } from "react"

import { IconDownload, IconExternalLink, IconFile, IconPhoto } from "@tabler/icons-react"

import type { TimelineEvent } from "@/pages/incidents/types"

type FileMeta = NonNullable<TimelineEvent["file"]>

function formatBytes(bytes: number | null | undefined): string | null {
  if (!bytes || bytes <= 0) {
    return null
  }
  const units = ["B", "KB", "MB", "GB"]
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }
  return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`
}

export function TimelineFileAttachment({ file, withDivider }: { file: FileMeta; withDivider: boolean }) {
  const [previewFailed, setPreviewFailed] = useState(false)
  const isImage = file.mimeType?.startsWith("image/") ?? false
  const Icon = isImage ? IconPhoto : IconFile
  const size = formatBytes(file.byteSize)
  const showInlineImage = isImage && Boolean(file.downloadUrl) && !previewFailed

  return (
    <div className={`rounded-md border border-border/60 bg-muted/30 ${withDivider ? "mt-3" : ""}`}>
      {showInlineImage && (
        <a
          href={file.downloadUrl!}
          target="_blank"
          rel="noopener noreferrer"
          className="block overflow-hidden rounded-t-md border-b border-border/60"
        >
          <img
            src={file.downloadUrl!}
            alt={file.name}
            className="max-h-80 w-full object-contain bg-background/40"
            loading="lazy"
            onError={() => setPreviewFailed(true)}
          />
        </a>
      )}
      <div className="flex items-center gap-3 px-3 py-2">
        <Icon className="size-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[12.5px] font-medium text-foreground">{file.name}</div>
          {size && (
            <div className="text-[11px] text-muted-foreground">{size}</div>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-1">
          {file.downloadUrl && (
            <a
              href={file.downloadUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex size-7 items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground"
              aria-label="Download file"
            >
              <IconDownload className="size-3.5" />
            </a>
          )}
          {file.slackPermalink && (
            <a
              href={file.slackPermalink}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex size-7 items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground"
              aria-label="Open in Slack"
            >
              <IconExternalLink className="size-3.5" />
            </a>
          )}
        </div>
      </div>
    </div>
  )
}
