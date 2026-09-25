import { useForm } from "@inertiajs/react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

interface CodeFormProps {
  action: string;
  label: string;
  submitLabel: string;
  hint?: string;
  // A recovery code is letters too, so the field only asks for digits where only digits fit.
  digitsOnly?: boolean;
}

// One field for the code and one button. The server says why a code was refused, and the field stays focused to retry.
export function CodeForm({ action, label, submitLabel, hint, digitsOnly = false }: CodeFormProps) {
  const form = useForm({ code: "" });

  function submit(event: React.FormEvent) {
    event.preventDefault();
    form.post(action, { preserveScroll: true, onError: clearCode });
  }

  function clearCode() {
    form.setData("code", "");
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-3">
      <Label htmlFor="operator-code">{label}</Label>
      <Input
        id="operator-code"
        autoFocus
        autoComplete="one-time-code"
        inputMode={digitsOnly ? "numeric" : "text"}
        spellCheck={false}
        value={form.data.code}
        onChange={(event) => form.setData("code", event.target.value)}
        className="h-11 text-center font-mono text-lg tracking-[0.3em]"
      />
      {form.errors.code ? (
        <p className="text-destructive text-sm">{form.errors.code}</p>
      ) : (
        hint && <p className="text-muted-foreground text-xs">{hint}</p>
      )}
      <Button type="submit" size="lg" disabled={form.processing || form.data.code.trim().length === 0}>
        {submitLabel}
      </Button>
    </form>
  );
}
