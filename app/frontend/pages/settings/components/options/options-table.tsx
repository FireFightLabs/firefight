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

import type { ConfigurableOption } from "@/pages/settings/lib/types"
import { reorderHandler } from "@/pages/settings/lib/reorder"
import { RadioGroup } from "@/components/ui/radio-group"
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { SortableOptionRow } from "@/pages/settings/components/options/sortable-option-row"

export function OptionsTable<T extends ConfigurableOption>({
  options,
  nameHeader,
  headers,
  cells,
  fallbackColor,
  onReorder,
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
  onReorder: (orderedIds: string[]) => void
  onMakeDefault: (id: string) => void
  onToggleEnabled: (option: T) => void
  onEdit: (option: T) => void
  onDelete: (option: T) => void
}) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      modifiers={[ restrictToVerticalAxis ]}
      onDragEnd={reorderHandler(options, onReorder)}
    >
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead className="w-8" />
            <TableHead>{nameHeader}</TableHead>
            {headers}
            <TableHead className="w-24 text-center">Default</TableHead>
            <TableHead className="w-24 text-center">Enabled</TableHead>
            <TableHead className="w-12" />
          </TableRow>
        </TableHeader>
        {/* table-row-group overrides RadioGroup's own grid display. */}
        <RadioGroup
          asChild
          className="table-row-group"
          value={options.find((option) => option.isDefault)?.id ?? ""}
          onValueChange={onMakeDefault}
        >
          <TableBody>
            <SortableContext
              items={options.map((option) => option.id)}
              strategy={verticalListSortingStrategy}
            >
              {options.map((option) => (
                <SortableOptionRow
                  key={option.id}
                  option={option}
                  fallbackColor={fallbackColor}
                  onToggleEnabled={() => onToggleEnabled(option)}
                  onEdit={() => onEdit(option)}
                  onDelete={() => onDelete(option)}
                >
                  {cells?.(option)}
                </SortableOptionRow>
              ))}
            </SortableContext>
          </TableBody>
        </RadioGroup>
      </Table>
    </DndContext>
  )
}
