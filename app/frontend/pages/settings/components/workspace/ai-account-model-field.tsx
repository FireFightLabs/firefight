import { SearchableSelect } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import type { AiProviderOption } from "@/types/serializers"

// A provider whose models the registry lists is picked from the list. One whose models are the customer's own names,
// such as an Azure deployment, is typed.
export function AiAccountModelField({
  id,
  label,
  hint,
  provider,
  value,
  error,
  onChange,
}: {
  id: string
  label: string
  hint: string
  provider: AiProviderOption | undefined
  value: string
  error: string | null
  onChange: (value: string) => void
}) {
  const options = (provider?.chatModels ?? []).map((model) => ({ value: model, label: model }))

  function choose(chosen: string | null) {
    onChange(chosen ?? "")
  }

  function type(event: React.ChangeEvent<HTMLInputElement>) {
    onChange(event.target.value)
  }

  return (
    <div className="flex flex-col gap-2">
      <Label htmlFor={id}>{label}</Label>
      {options.length > 0 ? (
        <SearchableSelect
          value={value || null}
          onValueChange={choose}
          options={options}
          placeholder="Choose a model"
          searchPlaceholder="Search models"
          emptyText="No model by that name"
        />
      ) : (
        <Input id={id} value={value} onChange={type} placeholder="The model or deployment name" />
      )}
      {error ? <p className="text-xs text-destructive">{error}</p> : <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  )
}
