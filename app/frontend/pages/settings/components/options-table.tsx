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
  // Keeps the Default column in place but drops its controls, for a table whose
  // rows can never hold the default. Alignment stays consistent with the tables
  // beside it rather than the column vanishing.
  defaultSelectable?: boolean
  // Explains the Default column when one table alone does not make its scope
  // obvious, as with statuses split across a card per lifecycle stage.
  defaultHeaderHint?: string
  // Sizes columns from the header rather than from content, so sibling tables
  // rendered one above another line up instead of each measuring its own rows.
  fixedLayout?: boolean
  // Turns each name into a button. Omitted by lists whose rows are settings
  // rather than content, which leaves the name as plain text.
  onSelect?: (option: T) => void
  onToggleEnabled: (option: T) => void
  onEdit: (option: T) => void
  onDelete: (option: T) => void
}) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))
  const { ordered, onDragEnd } = useOptimisticOrder(options)

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
          {reorderPath && <TableHead className="w-8" />}
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
          <TableHead className="w-16" />
        </TableRow>
      </TableHeader>
      <Rows options={ordered} onMakeDefault={defaultSelectable ? onMakeDefault : undefined}>
        {reorderPath ? (
          <SortableContext items={ordered.map((option) => option.id)} strategy={verticalListSortingStrategy}>
            {ordered.map((option) => <SortableOptionRow key={option.id} {...rowProps(option)} />)}
          </SortableContext>
        ) : (
          ordered.map((option) => <StaticOptionRow key={option.id} {...rowProps(option)} />)
        )}
      </Rows>
    </Table>
  )

  if (!reorderPath) {
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
// table-row-group overrides its own grid display when it becomes the tbody.
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
