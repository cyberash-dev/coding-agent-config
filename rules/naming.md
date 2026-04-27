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

## Variables
- Boolean variables are named as questions: `isNew`, `hasAccess`, `canEdit`
