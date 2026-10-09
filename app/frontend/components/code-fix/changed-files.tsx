import { type CodeFixWork, fileCounts, filesWord } from "@/lib/code-fix-work"

export function ChangedFiles({ work }: { work: CodeFixWork }) {
  if (work.files.length === 0) {
    return null
  }

  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="font-medium text-fg-primary">Changed {filesWord(work.files.length)}</span>
      <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
        {work.files.map((file) => (
          <li key={file.path} className="flex min-w-0 items-baseline gap-2 font-mono text-[11.5px]">
            <span className="min-w-0 truncate text-fg-secondary" title={file.path}>{file.path}</span>
            <span className="shrink-0 text-fg-muted">{fileCounts(file)}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
