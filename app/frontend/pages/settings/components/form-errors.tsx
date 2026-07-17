import { Alert, AlertDescription } from "@/components/ui/alert"

export function FormErrors({
  errors,
  className,
}: {
  errors: Record<string, string | string[]> | string[] | string | null | undefined
  className?: string
}) {
  const messages = !errors
    ? []
    : typeof errors === "string"
      ? [errors]
      : Array.isArray(errors)
        ? errors
        : Object.values(errors).flat()
  if (messages.length === 0) return null

  return (
    <Alert variant="destructive" className={className}>
      <AlertDescription>
        {messages.map((message, i) => (
          <p key={i}>{message}</p>
        ))}
      </AlertDescription>
    </Alert>
  )
}
