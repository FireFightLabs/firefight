import { type ChangeEvent, useEffect, useMemo, useRef, useState } from "react"
import {
  IconBold,
  IconCode,
  IconCodeblock,
  IconH2,
  IconH3,
  IconItalic,
  IconList,
  IconListNumbers,
  IconMarkdown,
} from "@tabler/icons-react"
import { EditorContent, useEditor, type Editor } from "@tiptap/react"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import {
  MarkdownParser,
  MarkdownSerializer,
  MarkdownSerializerState,
  defaultMarkdownParser,
  defaultMarkdownSerializer,
} from "prosemirror-markdown"
import type { Node as ProseMirrorNode, Schema } from "@tiptap/pm/model"

import { Textarea } from "@/components/ui/textarea"
import { Toggle } from "@/components/ui/toggle"
import { cn } from "@/lib/utils"

interface MarkdownEditorProps {
  value: string
  onChange: (markdown: string) => void
  placeholder?: string
  id?: string
  // Offers editing the Markdown itself, and opens a document there when the formatted view would lose some of it.
  allowSource?: boolean
  // The height the writing area starts at, such as min-h-56.
  minHeight?: string
}

const markdownSerializer = new MarkdownSerializer(
  {
    blockquote: defaultMarkdownSerializer.nodes.blockquote,
    paragraph: defaultMarkdownSerializer.nodes.paragraph,
    text: defaultMarkdownSerializer.nodes.text,
    heading: defaultMarkdownSerializer.nodes.heading,
    bulletList: defaultMarkdownSerializer.nodes.bullet_list,
    listItem: defaultMarkdownSerializer.nodes.list_item,
    hardBreak: defaultMarkdownSerializer.nodes.hard_break,
    codeBlock(state: MarkdownSerializerState, node: ProseMirrorNode) {
      const backticks = node.textContent.match(/`{3,}/gm)
      const fence = backticks ? `${backticks.sort().slice(-1)[0]}\`` : "```"
      state.write(fence + (node.attrs.language || "") + "\n")
      state.text(node.textContent, false)
      state.write("\n")
      state.write(fence)
      state.closeBlock(node)
    },
    orderedList(state: MarkdownSerializerState, node: ProseMirrorNode) {
      const start = node.attrs.start || 1
      const maxWidth = String(start + node.childCount - 1).length
      const space = state.repeat(" ", maxWidth + 2)
      state.renderList(node, space, (index) => {
        const numeral = String(start + index)
        return state.repeat(" ", maxWidth - numeral.length) + numeral + ". "
      })
    },
  },
  {
    italic: defaultMarkdownSerializer.marks.em,
    bold: defaultMarkdownSerializer.marks.strong,
    code: defaultMarkdownSerializer.marks.code,
  }
)

function buildParser(schema: Schema): MarkdownParser {
  return new MarkdownParser(schema, defaultMarkdownParser.tokenizer, {
    blockquote: { block: "blockquote" },
    paragraph: { block: "paragraph" },
    list_item: { block: "listItem" },
    bullet_list: { block: "bulletList" },
    ordered_list: {
      block: "orderedList",
      getAttrs: (tok) => ({ start: +(tok.attrGet("start") ?? 1) || 1 }),
    },
    heading: { block: "heading", getAttrs: (tok) => ({ level: +tok.tag.slice(1) }) },
    code_block: { block: "codeBlock", noCloseToken: true },
    fence: {
      block: "codeBlock",
      getAttrs: (tok) => ({ language: tok.info || null }),
      noCloseToken: true,
    },
    hardbreak: { node: "hardBreak" },
    em: { mark: "italic" },
    strong: { mark: "bold" },
    code_inline: { mark: "code", noCloseToken: true },
  })
}

function serialize(editor: Editor): string {
  if (editor.isEmpty) {
    return ""
  }
  return markdownSerializer.serialize(editor.state.doc)
}

// What the formatted view holds, by the names Markdown gives each piece. Anything else, such as a link, a table or an
// image, would be lost on save.
const KEPT = new Set([
  "blockquote", "paragraph", "list_item", "bullet_list", "ordered_list", "heading", "code_block", "fence", "hardbreak",
  "softbreak", "em", "strong", "code_inline", "inline", "text",
])

interface MarkdownToken {
  type: string
  children: MarkdownToken[] | null
}

function kept(token: MarkdownToken): boolean {
  return KEPT.has(token.type.replace(/_(open|close)$/, "")) && (token.children ?? []).every(kept)
}

function keepsEverything(markdown: string): boolean {
  const tokens: MarkdownToken[] = defaultMarkdownParser.tokenizer.parse(markdown, {})
  return tokens.every(kept)
}

// Writes Markdown in a formatted view, as runbooks and the handbook keep it. With allowSource the Markdown itself can be
// edited, which a document the formatted view cannot hold whole opens in, so nothing in it is lost on save.
export function MarkdownEditor({ value, onChange, placeholder, id, allowSource = false, minHeight = "min-h-56" }: MarkdownEditorProps) {
  const lastEmitted = useRef<string | null>(null)
  const [ source, setSource ] = useState(false)
  const [ sourceOnly, setSourceOnly ] = useState(false)

  const editor = useEditor({
    extensions: [
      StarterKit.configure({
        heading: { levels: [ 2, 3 ] },
        horizontalRule: false,
        link: false,
        strike: false,
        underline: false,
      }),
      Placeholder.configure({
        placeholder: placeholder ?? "Document the response procedure...",
      }),
    ],
    content: "",
    editorProps: {
      attributes: {
        class: cn("prose prose-sm dark:prose-invert max-w-none px-3 py-2 focus:outline-none", minHeight),
        ...(id ? { id } : {}),
      },
    },
    onUpdate: ({ editor }) => {
      const markdown = serialize(editor)
      lastEmitted.current = markdown
      onChange(markdown)
    },
  })

  const parser = useMemo(() => (editor ? buildParser(editor.schema) : null), [editor])

  useEffect(() => {
    if (!editor || !parser) {
      return
    }
    if (value === lastEmitted.current) {
      return
    }
    lastEmitted.current = value
    if (allowSource && !keepsEverything(value ?? "")) {
      setSource(true)
      setSourceOnly(true)
      return
    }
    editor.commands.setContent(parser.parse(value ?? ""), { emitUpdate: false })
  }, [editor, parser, value, allowSource])

  function writeSource(event: ChangeEvent<HTMLTextAreaElement>) {
    lastEmitted.current = event.target.value
    onChange(event.target.value)
  }

  // Back to the formatted view takes what was written as Markdown with it.
  function toggleSource(pressed: boolean) {
    if (!pressed && editor && parser) {
      editor.commands.setContent(parser.parse(value ?? ""), { emitUpdate: false })
    }
    setSource(pressed)
  }

  if (!editor) {
    return null
  }

  return (
    <div className="rounded-md border bg-transparent focus-within:border-ring focus-within:ring-[3px] focus-within:ring-ring/50">
      <div className="flex flex-wrap items-center gap-0.5 border-b p-1">
        {!source && (
          <>
            <Toggle size="sm" pressed={editor.isActive("heading", { level: 2 })} onPressedChange={() => editor.chain().focus().toggleHeading({ level: 2 }).run()} aria-label="Heading 2">
              <IconH2 />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("heading", { level: 3 })} onPressedChange={() => editor.chain().focus().toggleHeading({ level: 3 }).run()} aria-label="Heading 3">
              <IconH3 />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("bold")} onPressedChange={() => editor.chain().focus().toggleBold().run()} aria-label="Bold">
              <IconBold />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("italic")} onPressedChange={() => editor.chain().focus().toggleItalic().run()} aria-label="Italic">
              <IconItalic />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("code")} onPressedChange={() => editor.chain().focus().toggleCode().run()} aria-label="Inline code">
              <IconCode />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("bulletList")} onPressedChange={() => editor.chain().focus().toggleBulletList().run()} aria-label="Bullet list">
              <IconList />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("orderedList")} onPressedChange={() => editor.chain().focus().toggleOrderedList().run()} aria-label="Ordered list">
              <IconListNumbers />
            </Toggle>
            <Toggle size="sm" pressed={editor.isActive("codeBlock")} onPressedChange={() => editor.chain().focus().toggleCodeBlock().run()} aria-label="Code block">
              <IconCodeblock />
            </Toggle>
          </>
        )}
        {allowSource && (
          <Toggle size="sm" className="ml-auto gap-1 px-2 text-xs" pressed={source} disabled={sourceOnly} onPressedChange={toggleSource} aria-label="Edit as Markdown">
            <IconMarkdown />
            Markdown
          </Toggle>
        )}
      </div>
      {sourceOnly && (
        <p className="border-b px-3 py-1.5 text-xs text-muted-foreground">
          This page uses formatting the editor has no buttons for, such as links or tables, so it opens as Markdown to keep all of it.
        </p>
      )}
      {source ? (
        <Textarea
          id={id}
          value={value}
          onChange={writeSource}
          placeholder={placeholder}
          className={cn("resize-y rounded-none border-0 font-mono text-[13px] shadow-none focus-visible:ring-0", minHeight)}
        />
      ) : (
        <EditorContent editor={editor} />
      )}
    </div>
  )
}
