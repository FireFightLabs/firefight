import { useRef } from "react"
import type { InertiaFormProps } from "@inertiajs/react"

export function useSyncFormData<TKey, TForm extends Record<string, unknown>>(
  key: TKey,
  form: InertiaFormProps<TForm>,
  toFormData: () => TForm,
): void {
  const prevKey = useRef(key)
  if (key !== prevKey.current) {
    prevKey.current = key
    form.setData(toFormData())
  }
}
