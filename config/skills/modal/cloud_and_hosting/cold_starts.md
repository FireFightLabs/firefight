---
name: modal_cold_starts
when: A Modal app answers slowly, inputs wait in a queue, or the first call after a quiet spell is slow
tools: [resource_status, app_logs, update_autoscaler]
---
1. Call `resource_status` for the function's containers. Modal starts a container when no warm one is free, which is a cold start, and its functions scale to zero when idle unless they keep some running.
2. Call `app_logs` for the `function` around the slow calls. A cold start costs the container boot plus everything the code does in global scope and in its enter methods, such as imports or loading a model. A model downloaded at start is the usual cause of starts that take minutes.
3. The lasting fix is in the code: load weights ahead of time onto a volume, import less at start, or snapshot memory. Say which one fits what the logs show.
4. While that is built, `update_autoscaler` keeps containers warm. `min_containers` keeps that many running even with no work, `buffer_containers` keeps spares while the function is busy, and `scaledown_window` makes idle containers wait longer before they stop. Warm containers cost money while they wait, so name the cost before asking for it.
5. `max_containers` caps how many run at once. A cap set too low makes inputs queue under load, which looks like slowness rather than errors.
6. A change through `update_autoscaler` lasts until the app is deployed again, which puts back what the code says. Say that the code needs the same change for it to stay.
