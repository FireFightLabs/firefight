import type { ReactNode } from "react"
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core"
import { restrictToVerticalAxis } from "@dnd-kit/modifiers"
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable"

import { router } from "@inertiajs/react"

import type { ConfigurableOption } from "@/pages/settings/lib/types"
import { useOptimisticOrder } from "@/pages/settings/lib/reorder"
import { cn } from "@/lib/utils"
import { RadioGroup } from "@/components/ui/radio-group"
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { HeaderHint } from "@/pages/settings/components/header-hint"
import { SortableOptionRow, StaticOptionRow } from "@/pages/settings/components/sortable-option-row"

export function OptionsTable<T extends ConfigurableOption>({
  options,
  nameHeader,
  headers,
  cells,
  fallbackColor,
  reorderPath,
  reorderParams,
  onMakeDefault,
  defaultSelectable = true,
  defaultHeaderHint,
  fixedLayout = false,
  onSelect,
  onToggleEnabled,
  onEdit,
  onDelete,
  readOnly = false,
}: {
  options: T[]
  nameHeader: string
  // Extra columns sitting between the name and the Default column.
  headers?: ReactNode
  cells?: (option: T) => ReactNode
  fallbackColor?: string
  // Omitted when the order carries no meaning, which drops the drag handle.
  reorderPath?: string
  reorderParams?: Record<string, string>
  // Omitted for lists without a workspace default, which drops the column.
  onMakeDefault?: (id: string) => void
  // Keeps the Default column but drops its controls, so tables beside each
  // other stay aligned.
  defaultSelectable?: boolean
  // Explains the Default column where one table alone does not make its scope
  // obvious, as with statuses split across a card per stage.
  defaultHeaderHint?: string
  // Sizes columns from the header, so sibling tables stacked vertically line up.
  fixedLayout?: boolean
  // Turns each name into a button. Omitted where rows are settings rather
  // than content.
  onSelect?: (option: T) => void
  onToggleEnabled: (option: T) => void
  onEdit: (option: T) => void
  onDelete: (option: T) => void
  // For a viewer the gateway would refuse. No drag handle, switches, default
  // picker or row menu.
  readOnly?: boolean
}) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))
  const { ordered, onDragEnd } = useOptimisticOrder(options)
  const sortable = Boolean(reorderPath) && !readOnly

  function submitOrder(orderedIds: string[], onFailure: () => void) {
    if (!reorderPath) {
      return
    }

    router.patch(reorderPath, { ...reorderParams, ordered_ids: orderedIds }, {
      preserveScroll: true,
      onError: onFailure,
    })
  }

  const rowProps = (option: T) => ({
    option,
    fallbackColor,
    showDefault: Boolean(onMakeDefault),
    defaultSelectable,
    readOnly,
    onSelect: onSelect && (() => onSelect(option)),
    onToggleEnabled: () => onToggleEnabled(option),
    onEdit: () => onEdit(option),
    onDelete: () => onDelete(option),
    children: cells?.(option),
  })

  const table = (
    <Table className={cn(fixedLayout && "table-fixed")}>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          {sortable && <TableHead className="w-8" />}
          <TableHead className={cn(fixedLayout && "w-56")}>{nameHeader}</TableHead>
          {headers}
          {onMakeDefault && (
            <TableHead className="w-24 text-center">
              {!defaultSelectable ? null : defaultHeaderHint ? <HeaderHint label="Default" hint={defaultHeaderHint} /> : "Default"}
            </TableHead>
          )}
          <TableHead className="w-24 text-center">Enabled</TableHead>
          {/* 64px is what auto layout settles on for the button plus its cell
              padding, so a fixed-layout table lands in the same place. */}
          {!readOnly && <TableHead className="w-16" />}
        </TableRow>
      </TableHeader>
      <Rows options={ordered} onMakeDefault={defaultSelectable && !readOnly ? onMakeDefault : undefined}>
        {sortable ? (
          <SortableContext items={ordered.map((option) => option.id)} strategy={verticalListSortingStrategy}>
            {ordered.map((option) => <SortableOptionRow key={option.id} {...rowProps(option)} />)}
          </SortableContext>
        ) : (
          ordered.map((option) => <StaticOptionRow key={option.id} {...rowProps(option)} />)
        )}
      </Rows>
    </Table>
  )

  if (!sortable) {
    return table
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      modifiers={[ restrictToVerticalAxis ]}
      onDragEnd={(event) => onDragEnd(event, submitOrder)}
    >
      {table}
    </DndContext>
  )
}

// The radio group only exists when there is a default to pick, and
// table-row-group overrides its grid display when it becomes the tbody.
function Rows({
  options,
  onMakeDefault,
  children,
}: {
  options: ConfigurableOption[]
  onMakeDefault?: (id: string) => void
  children: ReactNode
}) {
  if (!onMakeDefault) {
    return <TableBody>{children}</TableBody>
  }

  return (
    <RadioGroup
      asChild
      className="table-row-group"
      value={options.find((option) => option.isDefault)?.id ?? ""}
      onValueChange={onMakeDefault}
    >
      <TableBody>{children}</TableBody>
    </RadioGroup>
  )
}
