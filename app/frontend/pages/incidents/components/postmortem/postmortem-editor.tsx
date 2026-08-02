import { useCallback, useRef, useState } from "react"
import { toast } from "sonner"
import {
  IconBold,
  IconCode,
  IconItalic,
  IconSparkles,
  IconStrikethrough,
  IconUnderline,
} from "@tabler/icons-react"
import { useEditor, EditorContent } from "@tiptap/react"
import { BubbleMenu } from "@tiptap/react/menus"
import { DOMSerializer } from "@tiptap/pm/model"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import TaskList from "@tiptap/extension-task-list"
import TaskItem from "@tiptap/extension-task-item"
import UnderlineExt from "@tiptap/extension-underline"
import Typography from "@tiptap/extension-typography"

import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import { AiRewriteDialog } from "@/pages/incidents/components/postmortem/ai-rewrite-dialog"
import { AiPendingExtension, aiPendingKey } from "@/pages/incidents/components/postmortem/ai-pending-extension"
import { incidentPostmortemAiRewritePath } from "@/lib/routes"
import { postJson } from "@/lib/http"

interface PostmortemEditorProps {
  content?: string
  onUpdate?: (html: string) => void
  incidentId?: string
}

export function PostmortemEditor({ content, onUpdate, incidentId }: PostmortemEditorProps) {
  const [aiSelection, setAiSelection] = useState<{ from: number; to: number; html: string } | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  const editor = useEditor({
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
      }),
      Placeholder.configure({
        placeholder: ({ node }) => {
          if (node.type.name === "heading") {
            return "Heading"
          }
          return "Start writing, or press '/' for commands..."
        },
      }),
      TaskList,
      TaskItem.configure({ nested: true }),
      UnderlineExt,
      Typography,
      AiPendingExtension,
    ],
    content: content || "",
    editorProps: {
      attributes: {
        class: "postmortem-content focus:outline-none",
      },
    },
    onUpdate: ({ editor }) => {
      onUpdate?.(editor.getHTML())
    },
  })

  const handleRewrite = useCallback(async (instruction: string) => {
    if (!editor || !aiSelection || !incidentId) {
      return
    }

    const { from, to, html } = aiSelection
    setAiSelection(null)

    editor.view.dispatch(editor.state.tr.setMeta(aiPendingKey, { range: { from, to } }))

    abortRef.current?.abort()
    const controller = new AbortController()
    abortRef.current = controller

    try {
      const { ok, data } = await postJson<{ rewritten_html: string; error?: string }>(
        incidentPostmortemAiRewritePath(incidentId),
        { selected_html: html, instruction },
        { signal: controller.signal }
      )
      if (!ok || !data) {
        throw new Error(data?.error || "Failed to rewrite")
      }

      const { rewritten_html } = data

      const pluginState = aiPendingKey.getState(editor.view.state)
      const currentRange = pluginState?.range
      if (!currentRange) {
        return
      }

      editor
        .chain()
        .focus()
        .setTextSelection({ from: currentRange.from, to: currentRange.to })
        .deleteSelection()
        .insertContent(rewritten_html)
        .run()
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") {
        return
      }
      editor.view.dispatch(editor.state.tr.setMeta(aiPendingKey, { range: null }))
      toast.error(err instanceof Error ? err.message : "Failed to rewrite")
    } finally {
      if (abortRef.current === controller) {
        abortRef.current = null
      }
    }
  }, [editor, aiSelection, incidentId])

  if (!editor) {
    return null
  }

  return (
    <div className="relative">
      <BubbleMenu
        editor={editor}
        className="flex items-center gap-0.5 rounded-lg border bg-popover p-1 shadow-md"
      >
        <Button
          variant="ghost"
          size="icon"
          className={`size-7 ${editor.isActive("bold") ? "bg-accent" : ""}`}
          onClick={() => editor.chain().focus().toggleBold().run()}
          type="button"
        >
          <IconBold className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className={`size-7 ${editor.isActive("italic") ? "bg-accent" : ""}`}
          onClick={() => editor.chain().focus().toggleItalic().run()}
          type="button"
        >
          <IconItalic className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className={`size-7 ${editor.isActive("underline") ? "bg-accent" : ""}`}
          onClick={() => editor.chain().focus().toggleUnderline().run()}
          type="button"
        >
          <IconUnderline className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className={`size-7 ${editor.isActive("strike") ? "bg-accent" : ""}`}
          onClick={() => editor.chain().focus().toggleStrike().run()}
          type="button"
        >
          <IconStrikethrough className="size-3.5" />
        </Button>
        <Separator orientation="vertical" className="mx-0.5 h-4" />
        <Button
          variant="ghost"
          size="icon"
          className={`size-7 ${editor.isActive("code") ? "bg-accent" : ""}`}
          onClick={() => editor.chain().focus().toggleCode().run()}
          type="button"
        >
          <IconCode className="size-3.5" />
        </Button>
        {incidentId && (
          <>
            <Separator orientation="vertical" className="mx-0.5 h-4" />
            <Button
              variant="ghost"
              size="icon"
              className="size-7 text-primary"
              onMouseDown={(e) => {
                e.preventDefault()
                const { from, to } = editor.state.selection
                if (from === to) {
                  return
                }
                const slice = editor.state.doc.slice(from, to)
                const serializer = DOMSerializer.fromSchema(editor.schema)
                const container = document.createElement("div")
                container.appendChild(serializer.serializeFragment(slice.content))
                setAiSelection({ from, to, html: container.innerHTML })
              }}
              type="button"
              aria-label="Rewrite with AI"
            >
              <IconSparkles className="size-3.5" />
            </Button>
          </>
        )}
      </BubbleMenu>

      <EditorContent editor={editor} />

      {incidentId && (
        <AiRewriteDialog
          open={aiSelection !== null}
          onOpenChange={(open) => {
            if (!open) {
              setAiSelection(null)
            }
          }}
          onSubmit={handleRewrite}
        />
      )}
    </div>
  )
}
