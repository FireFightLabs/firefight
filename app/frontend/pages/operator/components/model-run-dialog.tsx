import { router } from "@inertiajs/react"
import { useState, type ReactNode } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { OPERATOR_REGRESSION_MODELS_PROP } from "@/pages/operator/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { useAction } from "@/pages/operator/hooks/use-action"
import type { OperatorHalonRegressionModel } from "@/types/serializers"

function loadModels() {
  router.reload({ only: [OPERATOR_REGRESSION_MODELS_PROP] })
}

// One id can be listed under several providers, so an option is named by both.
function modelKey(model: OperatorHalonRegressionModel): string {
  return `${model.provider}:${model.id}`
}

function modelOption(model: OperatorHalonRegressionModel): SearchableSelectOption {
  return { value: modelKey(model), label: `${model.name} (${model.provider})` }
}

// Starts a measuring run, the regression set or the chat bench, on a model the operator picks from the priced
// registry, which loads when the picker opens. Left on Halon's model it tests the prompt as deployed.
export function ModelRunDialog({
  open,
  onClose,
  title,
  description,
  action,
  models,
}: {
  open: boolean
  onClose: () => void
  title: string
  description: ReactNode
  action: string
  models?: OperatorHalonRegressionModel[]
}) {
  const [chosenKey, setChosenKey] = useState<string | null>(null)
  const { busy, post } = useAction()
  const chosen = (models ?? []).find((model) => modelKey(model) === chosenKey) ?? null

  function run() {
    post(action, { model: chosen?.id ?? null, provider: chosen?.provider ?? null })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor="run-model">Model</Label>
          <SearchableSelect
            id="run-model"
            value={chosenKey}
            onValueChange={setChosenKey}
            options={(models ?? []).map(modelOption)}
            placeholder="Halon's model"
            searchPlaceholder="Search models"
            emptyText={models ? "No model matches" : "Loading models"}
            onOpen={loadModels}
          />
          <p className="text-muted-foreground text-xs">Leave it on Halon&apos;s model to test the prompt as deployed.</p>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" onClick={run} disabled={busy}>
            Run
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
