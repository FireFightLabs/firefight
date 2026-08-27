import { Extension } from "@tiptap/core"
import { Plugin, PluginKey } from "@tiptap/pm/state"
import { Decoration, DecorationSet } from "@tiptap/pm/view"

interface AiPendingState {
  range: { from: number; to: number } | null
}

export const aiPendingKey = new PluginKey<AiPendingState>("ai-pending")

export const AiPendingExtension = Extension.create({
  name: "aiPending",

  addProseMirrorPlugins() {
    return [
      new Plugin<AiPendingState>({
        key: aiPendingKey,
        state: {
          init: () => ({ range: null }),
          apply(tr, prev) {
            const meta = tr.getMeta(aiPendingKey)
            if (meta !== undefined) {
              return meta
            }
            if (!prev.range) {
              return prev
            }
            const from = tr.mapping.map(prev.range.from)
            const to = tr.mapping.map(prev.range.to)
            return { range: from === to ? null : { from, to } }
          },
        },
        props: {
          decorations(state) {
            const pluginState = aiPendingKey.getState(state)
            const range = pluginState?.range
            if (!range) {
              return DecorationSet.empty
            }
            return DecorationSet.create(state.doc, [
              Decoration.inline(range.from, range.to, { class: "ai-pending" }),
            ])
          },
        },
      }),
    ]
  },
})
