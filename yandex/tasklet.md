# Tasklet v2

Multilingual platform for running automated tasks (builds, tests, data
processing, CI/CD operations). Successor to Sandbox tasks. I/O via protobuf,
flexible runtimes (YT, Sandbox, YP), sidecars for Arcadia/secrets/artifacts.

Web UI: https://tasklets.yandex-team.ru

Full schema and workflow are too large to inline — read these references when
working with `t.yaml` or tasklet code:

- `~/.claude/yandex/refs/tasklet-reference.md` — platform reference
  (concepts, `t.yaml` spec, CLI, runtimes, accounts, schema registry)
- `~/.claude/yandex/refs/tasklet-dev-guide.md` — development guide
  (SDK, sidecars, CI/CD tasks, `run_command`, debugging, agents)

Languages: Python, Java, Go, Node.js, Swift.
