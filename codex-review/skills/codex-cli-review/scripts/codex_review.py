import argparse
import json
import os
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path
from typing import TypeAlias


JsonPrimitive: TypeAlias = None | bool | int | float | str
JsonValue: TypeAlias = JsonPrimitive | list["JsonValue"] | dict[str, "JsonValue"]


def review_prompt(scope: str, rules: str) -> str:
    return f"""Use $code-review to review only the supplied scope.
Do not edit files or expand the requested scope.

<review_scope>
{scope}
</review_scope>

<additional_review_rules>
{rules}
</additional_review_rules>

Return the review in the required output schema."""


def codex_command(
    cwd: Path,
    schema_path: Path,
    output_path: Path,
    prompt: str,
) -> tuple[str, ...]:
    return (
        "codex",
        "exec",
        "-C",
        str(cwd),
        "--skip-git-repo-check",
        "--sandbox",
        "read-only",
        "--disable",
        "hooks",
        "--ephemeral",
        "--color",
        "never",
        "--output-schema",
        str(schema_path),
        "-o",
        str(output_path),
        prompt,
    )


def review_document(raw_review: str) -> str:
    document: JsonValue = json.loads(raw_review)
    required_fields = {"findings", "summary", "residual_risks", "tests_not_run"}
    if not isinstance(document, dict) or set(document) != required_fields:
        raise ValueError("Codex returned an invalid review document")
    if not isinstance(document["findings"], list):
        raise ValueError("Codex returned invalid review findings")
    if not isinstance(document["summary"], str):
        raise ValueError("Codex returned an invalid review summary")
    if not isinstance(document["residual_risks"], list):
        raise ValueError("Codex returned invalid residual risks")
    if not isinstance(document["tests_not_run"], list):
        raise ValueError("Codex returned invalid tests_not_run")
    return raw_review.strip()


def argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run a VCS-neutral Codex CLI review")
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--scope-file", type=Path, required=True)
    parser.add_argument("--rules-file", type=Path)
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    if os.environ.get("CODE_REVIEW_HOOK_ACTIVE") == "1":
        return 0

    namespace = argument_parser().parse_args(arguments)
    cwd: Path = namespace.cwd
    scope_file: Path = namespace.scope_file
    rules_file: Path | None = namespace.rules_file
    if not cwd.is_dir():
        print(f"Review directory does not exist: {cwd}", file=sys.stderr)
        return 2
    if not scope_file.is_file():
        print(f"Review scope file does not exist: {scope_file}", file=sys.stderr)
        return 2
    if rules_file is not None and not rules_file.is_file():
        print(f"Review rules file does not exist: {rules_file}", file=sys.stderr)
        return 2

    scope = scope_file.read_text(encoding="utf-8")
    rules = (
        rules_file.read_text(encoding="utf-8")
        if rules_file is not None
        else "Load and apply all applicable rules from the current context and target tree."
    )
    prompt = review_prompt(scope, rules)
    schema_path = Path(__file__).with_name("review-output.schema.json")

    with tempfile.TemporaryDirectory(prefix="codex-review-") as temporary_directory:
        output_path = Path(temporary_directory) / "review.json"
        command = codex_command(cwd.resolve(), schema_path, output_path, prompt)
        environment = os.environ.copy()
        environment["CODE_REVIEW_HOOK_ACTIVE"] = "1"
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        if completed.returncode != 0:
            print(completed.stderr.strip() or "Codex CLI review failed.", file=sys.stderr)
            return completed.returncode
        try:
            review = review_document(output_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print("Codex returned invalid review JSON.", file=sys.stderr)
            return 3
        except ValueError as error:
            print(str(error), file=sys.stderr)
            return 3

    print(review)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
