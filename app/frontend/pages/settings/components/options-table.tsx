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
import { RadioGroup } from "@/components/ui/radio-group"
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { SortableOptionRow } from "@/pages/settings/components/sortable-option-row"

export function OptionsTable<T extends ConfigurableOption>({
  options,
  nameHeader,
  headers,
  cells,
  fallbackColor,
  reorderPath,
  reorderParams,
  onMakeDefault,
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
  reorderPath: string
  reorderParams?: Record<string, string>
  // Omitted for lists without a workspace default, which drops the column.
  onMakeDefault?: (id: string) => void
  onToggleEnabled: (option: T) => void
  onEdit: (option: T) => void
  onDelete: (option: T) => void
}) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))
  const { ordered, onDragEnd } = useOptimisticOrder(options)

  function submitOrder(orderedIds: string[], onFailure: () => void) {
    router.patch(reorderPath, { ...reorderParams, ordered_ids: orderedIds }, {
      preserveScroll: true,
      onError: onFailure,
    })
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      modifiers={[ restrictToVerticalAxis ]}
      onDragEnd={(event) => onDragEnd(event, submitOrder)}
    >
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead className="w-8" />
            <TableHead>{nameHeader}</TableHead>
            {headers}
            {onMakeDefault && <TableHead className="w-24 text-center">Default</TableHead>}
            <TableHead className="w-24 text-center">Enabled</TableHead>
            <TableHead className="w-12" />
          </TableRow>
        </TableHeader>
        <Rows options={ordered} onMakeDefault={onMakeDefault}>
          <SortableContext
            items={options.map((option) => option.id)}
            strategy={verticalListSortingStrategy}
          >
            {ordered.map((option) => (
              <SortableOptionRow
                key={option.id}
                option={option}
                fallbackColor={fallbackColor}
                showDefault={Boolean(onMakeDefault)}
                onToggleEnabled={() => onToggleEnabled(option)}
                onEdit={() => onEdit(option)}
                onDelete={() => onDelete(option)}
              >
                {cells?.(option)}
              </SortableOptionRow>
            ))}
          </SortableContext>
        </Rows>
      </Table>
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
  if (!onMakeDefault) return <TableBody>{children}</TableBody>

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
