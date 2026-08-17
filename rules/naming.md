# Naming Conventions

## Classes & Types
- Names MUST start with an uppercase letter: `Animal`, `Car`
- Names reflect what the entity IS, not what it DOES
  - BAD: `FileReader` (describes action)
  - GOOD: `File` with method `read()`

## Methods
Two categories based on side effects:

| Category | Returns value? | Side effects? | Naming style | Example |
|----------|---------------|---------------|-------------- |---------|
| Query    | Yes           | No            | Noun          | `Cat.name()` |
| Command  | No (void)     | Yes           | Verb          | `Car.stop()` |
| Predicate| Boolean       | No            | Question      | `Animal.isFlying?` |

- Name a method or helper for the general concept it implements, not for the
  first caller or specific feature that needed it. If nothing in the body ties to
  that feature, drop the feature prefix.
  - BAD: `pay_sbp_commission_hint` for a helper whose text only says the commission is zero
  - GOOD: `zero_commission_hint`

## Variables
- A variable's name reflects WHAT the value IS, specific enough to read on
  its own. Avoid vague placeholders.
  - BAD: `data`, `flag`, `value`, `tmp`, `info`, `res`
  - GOOD: `unacknowledged_payments`, `merchants_by_id`, `created_from`
- Boolean variables are named as a question, and the question MUST name its
  subject and condition, never a bare adjective.
  - BAD: `allowed`, `valid`, `ok`, `done` (adjective with no subject)
  - GOOD: `is_new`, `has_access`, `can_edit`, `is_merchant_allowed_for_client_id`
- A name MUST NOT claim more than the value actually guarantees. If an attribute
  or boolean implies a broader condition than it really ensures, rename it to the
  exact thing it holds or fix the computation — a misleading name is a bug.
  - BAD: `is_split_enabled` on a merchant used to mean "BNPL is available to the
    user" (split-on-merchant does not guarantee BNPL for that user)
