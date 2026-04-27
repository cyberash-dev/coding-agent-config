# Architecture

## File Organization
- One file = one public class/type
- Exception: private helper classes that are not used outside the file

## Design Principles
- Follow SOLID principles
- Follow Clean Architecture: dependencies point inward, domain has no external dependencies

## Backend Architecture — Vertical Slice + Hexagonal
Code is organized by feature (vertical slice), not by technical layer. Each slice
is self-contained and owns its full stack. Inside a slice, Hexagonal (Ports &
Adapters) rules apply.

### Slice layout
```
features/
  <feature-name>/
    domain/           # entities, value objects, business rules — no framework deps
    application/      # use cases; orchestrate domain through ports
    ports/
      inbound/        # driving ports — entry contracts implemented by use cases
      outbound/       # driven ports — interfaces the application depends on
    adapters/
      inbound/        # driving adapters: HTTP handlers, CLI, message consumers
      outbound/       # driven adapters: DB repositories, external API clients, brokers
```

### Rules
- **Slice ownership** — a slice owns its domain, ports, and adapters. Cross-slice
  imports go through a shared kernel, never directly into another slice's internals.
- **Dependency direction inside a slice** — `adapters → ports → application → domain`.
  Domain depends on nothing external. Application depends only on domain and ports.
- **Ports define dependencies** — the application declares what it needs as a port;
  the adapter implements it. No direct imports of frameworks/drivers from
  `application/` or `domain/`.
- **Driving vs driven** — driving (inbound) adapters call the application;
  driven (outbound) adapters are called by the application. Don't mix them.
- **Shared kernel** — only truly cross-cutting domain primitives (e.g. `Money`,
  `UserId`) live in `shared/`. Use case logic never goes there.
- **No layer-based top-level folders** — avoid global `controllers/`, `services/`,
  `repositories/`. Those concerns live inside the relevant slice.

## Frontend Architecture — Feature-Sliced Design (FSD)
- Layers (top to bottom): `app` → `pages` → `widgets` → `features` → `entities` → `shared`
- Each layer can only import from layers below it
- Each slice contains: `ui/`, `model/`, `api/`, `lib/`, `config/`
