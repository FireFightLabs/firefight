import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  PERMISSION_GROUPS,
  TOTAL_SCOPES,
} from "@/pages/onboarding/lib/scope-permissions";

export function PermissionsDialog() {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <button
          type="button"
          className="mt-5 inline-flex w-full cursor-pointer items-center justify-center gap-1.5 rounded text-xs text-muted-foreground transition-colors hover:text-fg-primary"
        >
          See all {TOTAL_SCOPES} permissions
          <span aria-hidden="true" className="translate-y-[-0.5px]">
            →
          </span>
        </button>
      </DialogTrigger>

      <DialogContent
        style={{
          maxWidth: "560px",
          maxHeight: "min(85vh, 720px)",
          display: "grid",
          gridTemplateRows: "auto minmax(0, 1fr)",
        }}
        className="w-[calc(100vw-2rem)] gap-0 overflow-hidden border-border-strong bg-card p-0 shadow-popover [&>button]:text-fg-secondary [&>button]:hover:text-fg-primary"
      >
        <DialogHeader className="space-y-1.5 border-b border-border px-6 pt-6 pb-5 sm:text-left">
          <DialogTitle>Permissions Firefight needs</DialogTitle>
          <DialogDescription className="text-base font-medium leading-relaxed text-fg-primary">
            Slack groups these OAuth scopes by what they let Firefight do in
            your workspace.
          </DialogDescription>
        </DialogHeader>

        <div className="overflow-y-auto overscroll-contain">
          <div className="px-6 pt-7 pb-7">
            {PERMISSION_GROUPS.map((group) => (
              <section
                key={group.title}
                className="border-t border-border pt-8 first:border-t-0 first:pt-0"
              >
                <div className="mb-5">
                  <p className="text-xs font-semibold uppercase tracking-widest text-fg-muted tabular-nums">
                    {group.scopes.length} scope
                    {group.scopes.length === 1 ? "" : "s"}
                  </p>
                  <h3 className="mt-2 text-sm font-semibold text-fg-primary">
                    {group.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-fg-body">
                    {group.description}
                  </p>
                </div>

                <dl className="space-y-5 pb-2">
                  {group.scopes.map((scope) => (
                    <div key={scope.name} className="space-y-[7px]">
                      <dt>
                        <code className="inline-block rounded-[4px] bg-surface-hover px-[7px] py-[3px] font-mono text-xs font-semibold leading-none text-fg-primary">
                          {scope.name}
                        </code>
                      </dt>
                      <dd className="text-sm leading-relaxed text-fg-body">
                        {scope.explanation}
                        {scope.boundary ? (
                          <>
                            {" "}
                            <span className="italic text-fg-secondary">
                              {scope.boundary}
                            </span>
                          </>
                        ) : null}
                      </dd>
                    </div>
                  ))}
                </dl>
              </section>
            ))}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
