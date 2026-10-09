import type { ChangeEvent } from "react"

import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

interface TextFieldProps {
  id: string
  label: string
  value: string
  limit?: number
  rows?: number
  placeholder?: string
  optional?: boolean
  className?: string
  onChange: (value: string) => void
}

// A textarea that counts toward the server's limit when it has one, so the writer trims a long note before saving instead of hitting a refusal.
export function TextField({ id, label, value, limit, rows = 3, placeholder, optional = false, className = "", onChange }: TextFieldProps) {
  const over = limit !== undefined && value.length > limit

  function write(event: ChangeEvent<HTMLTextAreaElement>) {
    onChange(event.target.value)
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-baseline justify-between gap-3">
        <Label htmlFor={id}>
          {label} {optional && <span className="font-normal text-muted-foreground">(optional)</span>}
        </Label>
        {limit !== undefined && (
          <span className={`text-xs tabular-nums ${over ? "text-destructive" : "text-muted-foreground"}`}>
            {value.length} / {limit}
          </span>
        )}
      </div>
      <Textarea id={id} rows={rows} className={`resize-y ${className}`} placeholder={placeholder} value={value} onChange={write} aria-invalid={over} />
    </div>
  )
}
