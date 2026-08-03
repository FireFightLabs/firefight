// Update/remove/append mechanics for the editable row lists in the alert
// settings dialogs. Stateless on purpose: composes with useState, form
// setData, or controlled props.
export interface RowListOps<T> {
  update: (index: number, patch: Partial<T>) => void
  remove: (index: number) => void
  append: (row: T) => void
}

export function rowListOps<T>(rows: T[], onChange: (rows: T[]) => void): RowListOps<T> {
  return {
    update: (index, patch) => onChange(rows.map((row, event) => (event === index ? { ...row, ...patch } : row))),
    remove: (index) => onChange(rows.filter((_, event) => event !== index)),
    append: (row) => onChange([...rows, row]),
  }
}
