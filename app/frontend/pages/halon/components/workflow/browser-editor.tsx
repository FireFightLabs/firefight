import { IconPlus, IconX } from "@tabler/icons-react"
import { type ChangeEvent, useState } from "react"

import { BadgeMultiSelect } from "@/components/badge-multi-select"
import type { SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import {
  BROWSER_ACTION,
  BROWSER_ACTIONS,
  BROWSER_SENDING_ACTIONS,
  BROWSER_VIEWPORTS,
  type BrowserAction,
  WORKFLOW_BROWSER,
} from "@/lib/generated/constants"
import { isObject, type JsonObject } from "@/lib/tool-fields"

// How each action reads in the path, and the one field it is mostly told by.
const ACTION_LABELS: Record<BrowserAction, string> = {
  goto: "Go to",
  click: "Click",
  fill: "Type into",
  press: "Press a key",
  wait_for_text: "Wait for text",
  expect_text: "Expect text",
}

const NO_SEND = "none"

interface PathStep {
  key: string
  action: BrowserAction
  fields: Record<string, string>
}

// What each action asks, beside the action itself.
function asked(action: BrowserAction): { key: string; label: string; placeholder: string }[] {
  switch (action) {
  case BROWSER_ACTION.GOTO:
    return [ { key: "url", label: "Address", placeholder: "https://shop.example.com/cart" } ]
  case BROWSER_ACTION.CLICK:
    return [ { key: "text", label: "What it clicks, by its text", placeholder: "Checkout" } ]
  case BROWSER_ACTION.FILL:
    return [ { key: "label", label: "The field, by its label", placeholder: "Email" }, { key: "value", label: "What it types", placeholder: "test@example.com" } ]
  case BROWSER_ACTION.PRESS:
    return [ { key: "key", label: "The key", placeholder: "Enter" } ]
  default:
    return [ { key: "text", label: "The text", placeholder: "Order placed" } ]
  }
}

function isAction(value: unknown): value is BrowserAction {
  return (BROWSER_ACTIONS as readonly unknown[]).includes(value)
}

function pathSteps(config: JsonObject): PathStep[] {
  const saved = config[WORKFLOW_BROWSER.STEPS]
  return (Array.isArray(saved) ? saved : []).filter(isObject).map((step) => {
    const { action, ...rest } = step
    return {
      key: crypto.randomUUID(),
      action: isAction(action) ? action : BROWSER_ACTION.GOTO,
      fields: Object.fromEntries(Object.entries(rest).map(([ field, value ]) => [ field, String(value ?? "") ])),
    }
  })
}

function browserError(url: string, steps: PathStep[], sendStep: number | null, undo: string): string | null {
  if (!url.trim()) {
    return "Give the address it opens."
  }
  if (steps.length > WORKFLOW_BROWSER.MAX_STEPS) {
    return `A path has at most ${WORKFLOW_BROWSER.MAX_STEPS} steps.`
  }
  if (steps.some((step) => asked(step.action).some((field) => !step.fields[field.key]?.trim()))) {
    return "Fill in what each step of the path needs."
  }
  return sendStep !== null && !undo.trim() ? "Say how a person puts back what it sends." : null
}

interface BrowserEditorProps {
  idPrefix: string
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

// A Browser step: the address it opens, the screen sizes, whether it logs in with the site's saved test login, a short
// path of steps, and the one step allowed to send what the page sends, which makes the step a change with its undo.
export function BrowserEditor({ idPrefix, config, references, disabled, onChange }: BrowserEditorProps) {
  const [ url, setUrl ] = useState(() => String(config[WORKFLOW_BROWSER.URL] ?? ""))
  const [ viewports, setViewports ] = useState<string[]>(() => {
    const saved = config[WORKFLOW_BROWSER.VIEWPORTS]
    return Array.isArray(saved) ? saved.map(String) : Object.keys(BROWSER_VIEWPORTS)
  })
  const [ logIn, setLogIn ] = useState(() => config[WORKFLOW_BROWSER.LOG_IN] === true)
  const [ steps, setSteps ] = useState<PathStep[]>(() => pathSteps(config))
  const [ sendStep, setSendStep ] = useState<number | null>(() => {
    const saved = Number(config[WORKFLOW_BROWSER.SEND_STEP])
    return Number.isInteger(saved) && saved > 0 ? saved : null
  })
  const [ undo, setUndo ] = useState(() => String(config[WORKFLOW_BROWSER.UNDO] ?? ""))
  const viewportOptions = Object.entries(BROWSER_VIEWPORTS).map(([ value, label ]) => ({ value, label }))
  const sendable = steps.flatMap((step, index) => ((BROWSER_SENDING_ACTIONS as readonly string[]).includes(step.action) ? [ index + 1 ] : []))

  function send(next: { url?: string; viewports?: string[]; logIn?: boolean; steps?: PathStep[]; sendStep?: number | null; undo?: string }) {
    const nextUrl = next.url ?? url
    const nextSteps = next.steps ?? steps
    const nextSend = next.sendStep === undefined ? sendStep : next.sendStep
    const nextUndo = next.undo ?? undo
    const written: JsonObject = {
      [WORKFLOW_BROWSER.URL]: nextUrl.trim(),
      [WORKFLOW_BROWSER.VIEWPORTS]: next.viewports ?? viewports,
      [WORKFLOW_BROWSER.LOG_IN]: next.logIn ?? logIn,
      [WORKFLOW_BROWSER.STEPS]: nextSteps.map((step) => ({ action: step.action, ...step.fields })),
    }
    if (nextSend !== null) {
      written[WORKFLOW_BROWSER.SEND_STEP] = nextSend
      written[WORKFLOW_BROWSER.UNDO] = nextUndo
    }
    onChange(written, browserError(nextUrl, nextSteps, nextSend, nextUndo))
  }

  function typedUrl(event: ChangeEvent<HTMLInputElement>) {
    setUrl(event.target.value)
    send({ url: event.target.value })
  }

  function insertedUrl(reference: string) {
    setUrl(`${url}${reference}`)
    send({ url: `${url}${reference}` })
  }

  function addViewport(value: string) {
    const next = [ ...viewports, value ]
    setViewports(next)
    send({ viewports: next })
  }

  function removeViewport(value: string) {
    const next = viewports.filter((each) => each !== value)
    setViewports(next)
    send({ viewports: next })
  }

  function toggledLogIn(checked: boolean) {
    setLogIn(checked)
    send({ logIn: checked })
  }

  function changeSteps(next: PathStep[]) {
    const stillSendable = sendStep !== null && next[sendStep - 1] && (BROWSER_SENDING_ACTIONS as readonly string[]).includes(next[sendStep - 1].action)
    const nextSend = stillSendable ? sendStep : null
    setSteps(next)
    setSendStep(nextSend)
    send({ steps: next, sendStep: nextSend })
  }

  function addStep() {
    changeSteps([ ...steps, { key: crypto.randomUUID(), action: BROWSER_ACTION.CLICK, fields: {} } ])
  }

  function removeStep(key: string) {
    return () => changeSteps(steps.filter((step) => step.key !== key))
  }

  function chooseAction(key: string) {
    return (value: string) => {
      if (isAction(value)) {
        changeSteps(steps.map((step) => (step.key === key ? { ...step, action: value, fields: {} } : step)))
      }
    }
  }

  function typedField(key: string, field: string) {
    return (event: ChangeEvent<HTMLInputElement>) => {
      changeSteps(steps.map((step) => (step.key === key ? { ...step, fields: { ...step.fields, [field]: event.target.value } } : step)))
    }
  }

  function chooseSend(value: string) {
    const next = value === NO_SEND ? null : Number(value)
    setSendStep(next)
    send({ sendStep: next })
  }

  function typedUndo(event: ChangeEvent<HTMLInputElement>) {
    setUndo(event.target.value)
    send({ undo: event.target.value })
  }

  return (
    <div className="space-y-4">
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-url`} className="text-xs">Address</Label>
        <div className="flex gap-1.5">
          <Input id={`${idPrefix}-url`} value={url} onChange={typedUrl} disabled={disabled} placeholder="https://shop.example.com" />
          {references.length > 0 && !disabled && <ReferencePicker references={references} label="Use an earlier value in the address" onPick={insertedUrl} />}
        </div>
      </div>
      <div className="space-y-1">
        <Label className="text-xs">Screen sizes</Label>
        <BadgeMultiSelect stacked selected={viewports} options={viewportOptions} placeholder="Add a screen size" onAdd={addViewport} onRemove={removeViewport} />
      </div>
      <div className="flex items-center gap-2">
        <Switch id={`${idPrefix}-log-in`} checked={logIn} onCheckedChange={toggledLogIn} disabled={disabled} />
        <Label htmlFor={`${idPrefix}-log-in`} className="text-xs">Log in first with the site&apos;s saved test login</Label>
      </div>
      <section className="space-y-2">
        <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">The path</h4>
        {steps.length === 0 && <p className="text-xs text-fg-muted">It opens the address and reads the page. Add steps to click, type or wait.</p>}
        {steps.map((step, index) => (
          <div key={step.key} className="space-y-1.5 rounded-md border border-border p-2">
            <div className="flex items-center gap-1.5">
              <span className="font-mono text-[11px] text-fg-muted">{index + 1}</span>
              <Select value={step.action} onValueChange={chooseAction(step.key)} disabled={disabled}>
                <SelectTrigger aria-label={`Step ${index + 1}'s action`} className="flex-1">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {BROWSER_ACTIONS.map((action) => <SelectItem key={action} value={action}>{ACTION_LABELS[action]}</SelectItem>)}
                </SelectContent>
              </Select>
              {!disabled && (
                <button type="button" aria-label={`Remove step ${index + 1}`} className="px-1 text-fg-muted hover:text-destructive" onClick={removeStep(step.key)}>
                  <IconX className="size-4" />
                </button>
              )}
            </div>
            {asked(step.action).map((field) => (
              <Input key={field.key} aria-label={field.label} placeholder={field.placeholder} value={step.fields[field.key] ?? ""} disabled={disabled}
                     onChange={typedField(step.key, field.key)} />
            ))}
          </div>
        ))}
        {!disabled && steps.length < WORKFLOW_BROWSER.MAX_STEPS && (
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addStep}>
            <IconPlus className="size-3.5" />
            Add a step
          </Button>
        )}
      </section>
      {sendable.length > 0 && (
        <div className="space-y-1">
          <Label className="text-xs">Send</Label>
          <Select value={sendStep === null ? NO_SEND : String(sendStep)} onValueChange={chooseSend} disabled={disabled}>
            <SelectTrigger aria-label="The step allowed to send" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={NO_SEND}>Send nothing, stop before it</SelectItem>
              {sendable.map((number) => <SelectItem key={number} value={String(number)}>Let step {number} send what the page sends</SelectItem>)}
            </SelectContent>
          </Select>
          <p className="text-xs text-fg-muted">Sending is a change. It never happens in a run nobody pressed, and only after the same path stopped just before it.</p>
        </div>
      )}
      {sendStep !== null && (
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-undo`} className="text-xs">How a person puts it back</Label>
          <Input id={`${idPrefix}-undo`} value={undo} onChange={typedUndo} disabled={disabled} placeholder="Cancel the test order in the admin" />
        </div>
      )}
    </div>
  )
}
