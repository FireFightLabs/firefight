import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import type { WorkflowInput } from "@/pages/halon/components/workflows/types"

// The questions a workflow's trigger asks, each with its default filled in, for a run by hand or a test.
export function InputsFields({
  idPrefix,
  inputs,
  values,
  onChange,
}: {
  idPrefix: string
  inputs: WorkflowInput[]
  values: Record<string, string>
  onChange: (key: string, value: string) => void
}) {
  if (inputs.length === 0) {
    return <p className="text-sm text-muted-foreground">It asks nothing before it runs.</p>
  }

  return (
    <div className="flex flex-col gap-4">
      {inputs.map((input) => (
        <div key={input.key} className="flex flex-col gap-2">
          <Label htmlFor={`${idPrefix}-${input.key}`}>{input.question}</Label>
          <Input
            id={`${idPrefix}-${input.key}`}
            value={values[input.key] ?? ""}
            placeholder={input.default ?? ""}
            onChange={(event) => onChange(input.key, event.target.value)}
          />
        </div>
      ))}
    </div>
  )
}

export function defaultValues(inputs: WorkflowInput[]): Record<string, string> {
  return Object.fromEntries(inputs.map((input) => [ input.key, input.default ?? "" ]))
}
