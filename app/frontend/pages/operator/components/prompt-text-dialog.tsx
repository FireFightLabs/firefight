import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { formatDateTime } from "@/lib/formatters"
import { whenClosed } from "@/lib/handlers"
import type { HalonPrompt } from "@/pages/operator/types"

export function PromptTextDialog({ prompt, onClose }: { prompt: HalonPrompt | null; onClose: () => void }) {
  return (
    <Dialog open={prompt !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle className="font-mono">{prompt?.version}</DialogTitle>
          <DialogDescription>The run prompt as it was worded from {prompt ? formatDateTime(prompt.firstSeenAt) : ""}.</DialogDescription>
        </DialogHeader>
        <pre className="bg-muted/40 max-h-[60vh] overflow-auto rounded-md border border-border p-4 font-mono text-xs whitespace-pre-wrap">{prompt?.text}</pre>
      </DialogContent>
    </Dialog>
  )
}
