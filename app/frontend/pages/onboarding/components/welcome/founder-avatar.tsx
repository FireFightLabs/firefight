import { useState } from "react"

export function FounderAvatar() {
  const [errored, setErrored] = useState(false)

  if (errored) {
    return (
      <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-full bg-secondary text-xs font-semibold tracking-tight text-foreground">
        UN
      </span>
    )
  }

  return (
    <img
      src="https://i.pravatar.cc/96?img=12"
      alt="Uros Nikolic"
      onError={() => setErrored(true)}
      className="size-11 shrink-0 rounded-full object-cover ring-1 ring-border"
    />
  )
}
