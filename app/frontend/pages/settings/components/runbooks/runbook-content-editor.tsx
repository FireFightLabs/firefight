import { useEffect, useMemo, useRef } from "react"
import {
  IconBold,
  IconCode,
  IconCodeblock,
  IconH2,
  IconH3,
  IconItalic,
  IconList,
  IconListNumbers,
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
} from "@tiptap/pm/markdown"
import type { Node as ProseMirrorNode, Schema } from "@tiptap/pm/model"

import { Toggle } from "@/components/ui/toggle"

interface RunbookContentEditorProps {
  value: string
  onChange: (markdown: string) => void
  placeholder?: string
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
  if (editor.isEmpty) return ""
  return markdownSerializer.serialize(editor.state.doc)
}

export function RunbookContentEditor({ value, onChange, placeholder }: RunbookContentEditorProps) {
  const lastEmitted = useRef<string | null>(null)

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
        class:
          "prose prose-sm dark:prose-invert max-w-none min-h-56 px-3 py-2 focus:outline-none",
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
    if (!editor || !parser) return
    if (value === lastEmitted.current) return
    lastEmitted.current = value
    const doc = parser.parse(value ?? "")
    editor.commands.setContent(doc, { emitUpdate: false })
  }, [editor, parser, value])

  if (!editor) return null

  return (
    <div className="rounded-md border bg-transparent focus-within:border-ring focus-within:ring-[3px] focus-within:ring-ring/50">
      <div className="flex flex-wrap items-center gap-0.5 border-b p-1">
        <Toggle
          size="sm"
          pressed={editor.isActive("heading", { level: 2 })}
          onPressedChange={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}
          aria-label="Heading 2"
        >
          <IconH2 />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("heading", { level: 3 })}
          onPressedChange={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}
          aria-label="Heading 3"
        >
          <IconH3 />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("bold")}
          onPressedChange={() => editor.chain().focus().toggleBold().run()}
          aria-label="Bold"
        >
          <IconBold />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("italic")}
          onPressedChange={() => editor.chain().focus().toggleItalic().run()}
          aria-label="Italic"
        >
          <IconItalic />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("code")}
          onPressedChange={() => editor.chain().focus().toggleCode().run()}
          aria-label="Inline code"
        >
          <IconCode />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("bulletList")}
          onPressedChange={() => editor.chain().focus().toggleBulletList().run()}
          aria-label="Bullet list"
        >
          <IconList />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("orderedList")}
          onPressedChange={() => editor.chain().focus().toggleOrderedList().run()}
          aria-label="Ordered list"
        >
          <IconListNumbers />
        </Toggle>
        <Toggle
          size="sm"
          pressed={editor.isActive("codeBlock")}
          onPressedChange={() => editor.chain().focus().toggleCodeBlock().run()}
          aria-label="Code block"
        >
          <IconCodeblock />
        </Toggle>
      </div>
      <EditorContent editor={editor} />
    </div>
  )
}
