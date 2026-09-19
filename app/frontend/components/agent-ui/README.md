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
| `task-rows.tsx` | `task-rows` | Dropped `min-h-[196px]`, which held their demo at a fixed height. |
| `prompt-bar.tsx` | `prompt-bar` | Dropped the `glimm` WebGL sweep, which played on model change. Added `sources`, `commands`, `modelPicker`, `dictation` and `busy` props, so the two controls with nothing behind them yet are off rather than shown and dead, and a menu with nothing in it does not open. Added `onSourceSearch`, which hands the @ query to the caller so it can search the server, and then shows `sources` as given rather than filtering them again. Added `sourceHint`, the line under the @ menu, since ours finds incidents and not files. |

Not vendored yet, and worth taking when there is something behind them: `thinking-state` (needs the
reasoning we already store), `streaming-text` (needs sources and follow-ups), `approval-card` (the
shape for pausing to ask a person).
