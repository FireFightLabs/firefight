import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog"
// Anything with a name and an address it is served from, such as a chat's file or a run's note file.
export interface ShownImage {
  name: string
  url: string
}

interface ImageDialogProps {
  image: ShownImage | null
  onOpenChange: (open: boolean) => void
}

// An image someone sent, at full size over the page, with a way to open the original on its own.
export function ImageDialog({ image, onOpenChange }: ImageDialogProps) {
  return (
    <Dialog open={image !== null} onOpenChange={onOpenChange}>
      <DialogContent className="grid max-h-[calc(100dvh-2rem)] w-auto max-w-[calc(100vw-2rem)] gap-3 p-4 sm:max-w-[calc(100vw-4rem)]">
        <DialogTitle className="truncate pr-8 text-[14px]">{image?.name}</DialogTitle>
        <DialogDescription className="sr-only">The image at full size</DialogDescription>
        {image && (
          <img src={image.url} alt={image.name} className="max-h-[calc(100dvh-8rem)] max-w-full justify-self-center rounded-md object-contain" />
        )}
        {image && (
          <a href={image.url} target="_blank" rel="noreferrer" className="justify-self-start text-[13px] text-ink-2 underline-offset-2 hover:underline">
            Open the original
          </a>
        )}
      </DialogContent>
    </Dialog>
  )
}
