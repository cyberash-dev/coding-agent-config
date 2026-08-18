# Orchestration

Delegation is a default execution mode, not an escalation. This file is
installed only when the operator asks for it, and its presence **is** their
standing request for sub-agents, delegation, and parallel agent work: spawn
them when the work fits the shape below, without asking first.

Delegating does not move responsibility. The result you hand back is yours,
including everything an agent did on your behalf.

## When to delegate

The trigger is independence, not size. Delegate as soon as the work splits
into parts that do not block each other:

- Two or more questions answerable on their own — recon, prior art, docs,
  "where is X used", "how does Y behave today".
- Review or audit along separate axes — correctness, security, tests,
  performance. One axis per agent, so no axis loses to another.
- Edits with disjoint write sets — one agent per group of files, never two
  agents in the same file.
- A verification, reproduction, or benchmark pass that can run while the
  implementation continues.

## When to keep it local

- Your immediate next step is blocked on the result. Delegation buys
  parallelism, not speed — waiting on a single agent is slower than doing it.
- The subtask is too coupled to state as a self-contained brief.
- The whole task is one edit, one command, or one answer.
- Instructions that govern your own behaviour (rules, skills, specs): read
  them yourself. Never delegate reading, summarizing, or interpreting them.
- The operator said to do it yourself. That cancels delegation for that task.

## How to delegate

- The brief stands alone: goal, paths in scope, the exact output you need
  back, and the write scope the agent owns. Agents do not inherit your
  conversation.
- One concrete deliverable per agent. "Explore the codebase" is not a task.
- Spawn the whole independent set in one round, then continue with local work
  that does not overlap it. Do not wait unless the critical path needs the
  result now.
- Never redo delegated work. Read what comes back, integrate it, verify it.
- Treat a report as evidence, not as proof. A claim that tests pass is checked
  by running them.

## Guardrails

- **Depth 1.** If you are yourself a sub-agent or a teammate, do the work.
  Do not re-delegate.
- **Disjoint write sets.** Two agents never own the same file. If the split
  cannot be made disjoint, it is one task, not two.
- **Bounded fan-out.** 3-5 agents covers almost every task. More agents means
  more coordination and more tokens, not more throughput.
- **Say what you delegated.** Name the agents and their scopes in your answer,
  and say what you dropped if you narrowed the fan-out.

## Harness mapping

|             | Claude Code                                             | Codex                                     |
|-------------|---------------------------------------------------------|-------------------------------------------|
| Spawn       | `Agent`; with a `name` it becomes a teammate when agent teams are on | `spawn_agent`                    |
| Message     | `SendMessage`                                            | `send_message`                            |
| Await       | the agent's result, or its idle notification             | `wait_agent`, only on the critical path   |
| Reusable roles | `~/.claude/agents/*.md`                               | `~/.codex/agents/*.toml`, built-in `worker` / `explorer` |

Claude Code spawns teammates only in an interactive session: under `-p`
(headless, SDK) a named sub-agent runs as an ordinary sub-agent.
