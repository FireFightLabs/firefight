# Beautiful UI components

Vendored from <https://www.beautifului.dev>, which publishes a shadcn-format registry:

```
npx shadcn add https://www.beautifului.dev/r/<name>.json
```

The files here were taken from that registry and kept close to source, so an update is a re-pull plus
the edits below rather than a rewrite. They are outside eslint (like `components/ui/`) because they
are not ours to reformat. Their tokens live in `app/frontend/styles/agent-ui.css`, scoped to
`.agent-ui`, which the agent page carries.

| File | Registry item | Our edits |
|---|---|---|
| `loading-state.tsx` | `loading-state` | Dropped the Surfer variant, which streams a meme video from their CDN. |
| `task-rows.tsx` | `task-rows` | Dropped `min-h-[196px]`, which held their demo at a fixed height. Added `waiting` and `cancelled` statuses, a muted badge and pill for a step paused on a person and for one they turned down. |
| `approval-card.tsx` | `approval-card` | A single question sends on the first click and hides the footer, since there is nothing to step through. Added `allowCustom` to turn off the "Something else" row. `send` takes the answers it sends, so the auto advance after the last choice sends that choice, where the original sent the answers from before the click. Imports point at `button.tsx` and `glide-menu.tsx` here. |
| `button.tsx` | `button` | None, it is what the approval card is built from. |
| `glide-menu.tsx` | `glide-menu` | None, it is what the approval card is built from. |
| `thinking-state.tsx` | `thinking-state` | Kept the Steps variant and dropped Reasoning, Search and Coding, which are demos of things we do not have yet. The trace is driven by props rather than by its own timer: rows show as they are given, `working` shimmers the header and spins the last row, and `done` carries our own wording. Dropped the fixed `minHeight`, which held their demo open. |
| `prompt-bar.tsx` | `prompt-bar` | Dropped the `glimm` WebGL sweep, which played on model change. Added `sources`, `commands`, `modelPicker`, `dictation` and `busy` props, so the two controls with nothing behind them yet are off rather than shown and dead, and a menu with nothing in it does not open. Added `onSourceSearch`, which hands the @ query to the caller so it can search the server, and then shows `sources` as given rather than filtering them again. Added `sourceHint`, the line under the @ menu, since ours finds incidents and not files. Added `initialDraft` and `autoFocus`, so a new chat can hand it an example question to finish with the caret already in place. |

Not vendored yet, and worth taking when there is something behind it: `streaming-text` (needs sources
and follow-ups).
