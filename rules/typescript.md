# TypeScript

Type-level discipline for TypeScript/JavaScript. Naming (PascalCase types,
`is/has/can` boolean prefixes) lives in `naming.md`; this file is about the type
system itself. The shared ESLint config enforces the mechanical half.

## Type Safety
- **No `any`** — neither as an annotation nor via `as any`. Narrow the type. At a
  genuine boundary use `unknown` and narrow before use, never `any`.
  (`@typescript-eslint/no-explicit-any`)
- **No non-null assertions (`x!`)**. Prove non-null through control flow or
  narrowing, or handle the `null`/`undefined` branch. A bang only hides the case.
  (`@typescript-eslint/no-non-null-assertion`)
- **No unsafe type assertions.** `as` is for safe widening and `as const` only;
  never narrow with `as`, and never the `x as unknown as T` escape hatch. If a
  value isn't the type you want, fix the source type or narrow at runtime.
  (`@typescript-eslint/no-unsafe-type-assertion`)
- **Prefer the specific type over the generic** (same spirit as `python.md`):
  - `ReadonlyArray<X>` / `readonly` fields when you don't mutate.
  - `Record<K, V>` or a branded domain type over a bare object.
  - String-literal unions or `enum` over `string` for a closed set of values.
  - Domain types (`UserId`, `Money`) over raw primitives.

The type-checked rule family (`no-unsafe-assignment` / `-return` /
`-member-access` / `-argument` / `-call`) follows from the same principle: a
value typed `any` leaking through the program is a hole in the contract. Close
it at the source, don't silence the rule.

## Async Safety
- **No floating promises** — every promise is `await`ed, `return`ed, or
  explicitly discarded with `void`. A dropped promise swallows both the result
  and the rejection. (`@typescript-eslint/no-floating-promises`)
- **No misused promises** — don't pass an `async` function where a synchronous
  `void` callback is expected, and don't put a promise in a boolean/condition
  position. (`@typescript-eslint/no-misused-promises`)
- **Only `await` a thenable.** Awaiting a non-promise is a bug or a misread type.
  (`@typescript-eslint/await-thenable`)

## Fail fast over defensive casts
Casting (`as`) and non-null bangs are the type-level equivalent of swallowing an
exception (see `errors.md`): they paper over a state the types say is possible.
Validate at the boundary, narrow honestly, and let the type system surface the
case you'd otherwise assert away.
