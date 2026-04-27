# infractl (Infrastructure as Code)

Infrastructure managed via `i.yaml` and `i.<kind>.<name>.yaml`. Full schema is
too large to inline — read these references when working with specs:

- `~/.claude/yandex/refs/infractl-reference.md` —
  Runtime schema, CLI, CI integration
- `~/.claude/yandex/refs/infractl-objects.md` —
  object types (awacs, alerts, TVM, etc.)

## File naming
- `i.yaml` — namespace/environment metadata
- `i.<kind>.<name>.yaml` — object spec (e.g. `i.runtime.backend.yaml`)
- `i.<kind>.<name>.base.yaml` — base template (NOT deployed, inheritance only)
- Inheritance: `from: ../i.<...>.base.yaml` — child overrides parent fields

## Secret syntax
- `${sec-ID:ver-ID:key}` — pinned to version
- `${sec-ID:key}` — latest version
- `${file-ref:path}` — file reference
- `${package:path}` — package reference

## CLI

```
ya tool infractl bootstrap [trial]       # create service
ya tool infractl make / build / diff     # compile, build artifacts, preview
ya tool infractl deploy [--artifacts]    # deploy
ya tool infractl status                  # check status
ya tool infractl pull <ns> <kind>/<name> # download from K8s
ya tool infractl modify delegate yp|awacs|nanny -n <ns>
ya tool infractl import application|stage|nanny
```
