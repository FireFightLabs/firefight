// Update/remove/append mechanics for the editable row lists in the alert
// settings dialogs. Stateless on purpose: composes with useState, form
// setData, or controlled props.

export interface RowListItem {
  rowId: string
}

export interface RowListOps<T> {
  update: (index: number, patch: Partial<T>) => void
  remove: (index: number) => void
  append: (row: T) => void
}

let lastRowId = 0

export function newRow<T>(row: T): T & RowListItem {
  lastRowId += 1
  return { ...row, rowId: String(lastRowId) }
}

export function withRowIds<T>(rows: T[]): (T & RowListItem)[] {
  return rows.map((row) => newRow(row))
}

export function rowListOps<T extends RowListItem>(rows: T[], onChange: (rows: T[]) => void): RowListOps<T> {
  return {
    update: (index, patch) => onChange(rows.map((row, position) => (position === index ? { ...row, ...patch } : row))),
    remove: (index) => onChange(rows.filter((_, position) => position !== index)),
    append: (row) => onChange([...rows, row]),
  }
}
