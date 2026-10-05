> ## Documentation Index
> Fetch the complete documentation index at: https://docs.fly.io/llms.txt
> Use this file to discover all available pages before exploring further.

# Machine restart policy

The Machine restart policy defines whether and how flyd restarts a Machine after its main process exits. The restart policy applies per Machine, and is not an app-wide setting.

The restart policies are:

* **`no`**: Never try to restart a Machine automatically when its main process exits, whether that’s on purpose or on a crash. `no` is the default when you use the `--rm` option to create a Machine with `fly m run` that auto-destroys on exit.

* **`always`**: Always restart a Machine automatically and never let it enter a `stopped` state, even when the main process exits cleanly. `always` is the default when you create a Machine with `fly m run` and for Fly Postgres app Machines. Recommended for "always-on" apps with no services configured, since the Machine restarts regardless of the exit code.

* **`on-fail`** (or **`on-failure`** for the Machines API and when viewed in the Machine config): Try up to `max_retries` (default 10) times within a 5-minute window to automatically restart the Machine if it exits with a non-zero exit code, before letting it stop. Recommended for most Machines with services configured, since Fly Proxy can wake them on request. `on-fail` lets Machines be restarted if they crash, and allows your app Machines to effectively scale down by exiting cleanly. `on-fail` is the default when there's no explicit restart policy in a Machine's config, such as Machines created by `fly launch` and `fly deploy`. Machines with a schedule also default to the `on-fail` restart policy.

<h2 id="check-a-machines-restart-policy">
  Check a Machine's restart policy
</h2>

Display a Machine's status and its config in `json` format:

```bash theme={null}
fly m status -d <machine id> 
```

Example output with a restart policy of `always`:

```out theme={null}
...
Config:
{
  "init": {},
  "image": "registry-1.docker.io/flyio/hellofly:latest",
  "restart": {
    "policy": "always"
  },
  "guest": {
    "cpu_kind": "shared",
    "cpus": 1,
    "memory_mb": 256
  },
  "dns": {}
}
```

<h2 id="change-a-machines-restart-policy-with-flyctl">
  Change a Machine's restart policy with flyctl
</h2>

Update the Machine config:

```bash theme={null}
fly m update <machine id> --restart <no | always | on-fail>
```

The following example updates a Machine's restart policy to `on-fail`:

<CodeGroup>
  ```bash cmd theme={null}
  fly m update 3908032c794088 --restart on-fail
  ```

  ```out out theme={null}
  Configuration changes to be applied to machine: 3908032c794088 (my-app-name)

    	... // 2 identical lines
    	  "image": "registry-1.docker.io/flyio/hellofly:latest",
    	  "restart": {
  - 	    "policy": "always"
  + 	    "policy": "on-failure"
    	  },
    	  "guest": {
    	... // 6 identical lines

  ? Apply changes? (y/N)
  ```
</CodeGroup>

Enter `y` to apply the changes.

<h2 id="change-a-machines-restart-policy-with-the-machines-api">
  Change a Machine's restart policy with the Machines API
</h2>

With the Machines API, you can set the restart policy, and the maximum number of retries when the policy is `on-failure`.

<Note>
  **Important:** The API and the returned Machine config use `on-failure` instead of `on-fail`.
</Note>

Endpoint: `POST /apps/{app_name}/machines/{machine_id}`

For example:

```
...
    "restart": {
      "max_retries": 5,
      "policy": "on-failure"
    },
...
```

Refer to the Machines API docs for more information about [updating a Machine](/machines/api/machines-resource#update-a-machine).

## Set a restart policy in your fly.toml

You can also set a default app-level restart policy in your fly.toml file:

```toml theme={null}
[[restart]]
  policy = "<never | always | on-failure>"
  retries = 10
  processes = ["app"]
```

A restart policy can be targeted to a specific process group. If a group is not specified, all machines in an app will have the same default restart policy. If needed, you can still apply different policies on individual machines using the flyctl or Machines API methods above.
