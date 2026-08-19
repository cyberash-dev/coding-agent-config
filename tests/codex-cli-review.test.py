from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import TypedDict
from unittest.mock import patch


SCRIPTS_DIR = (
    Path(__file__).parents[1] / "codex-review" / "skills" / "codex-cli-review" / "scripts"
)
REVIEW_SCRIPT = SCRIPTS_DIR / "codex_review.py"
sys.path.insert(0, str(SCRIPTS_DIR))

from codex_review import codex_command, main, review_prompt  # noqa: E402


class ReviewFinding(TypedDict):
    priority: str
    title: str
    body: str
    file: str
    line: int | None
    rule: str | None
    remediation: str


class ReviewDocument(TypedDict):
    findings: list[ReviewFinding]
    summary: str
    residual_risks: list[str]
    tests_not_run: list[str]


def fake_codex(directory: Path, review: ReviewDocument) -> Path:
    return fake_codex_output(directory, json.dumps(review))


def fake_codex_output(directory: Path, output: str) -> Path:
    executable = directory / "codex"
    executable.write_text(
        """#!/usr/bin/env python3
import pathlib
import sys

output_path = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
output_path.write_text(%r, encoding="utf-8")
"""
        % output,
        encoding="utf-8",
    )
    executable.chmod(0o755)
    return executable


class ReviewPromptTest(unittest.TestCase):
    def test_prompt_encapsulates_review_contract(self: ReviewPromptTest) -> None:
        scope = "Review only src/payment.py from the supplied diff."
        rules = "Never log payment credentials."

        prompt = review_prompt(scope, rules)

        self.assertEqual(
            prompt,
            """Use $code-review to review only the supplied scope.
Do not edit files or expand the requested scope.

<review_scope>
Review only src/payment.py from the supplied diff.
</review_scope>

<additional_review_rules>
Never log payment credentials.
</additional_review_rules>

Return the review in the required output schema.""",
        )


class CodexCommandTest(unittest.TestCase):
    def test_command_runs_read_only_without_git_or_hooks(self: CodexCommandTest) -> None:
        cwd = Path("/workspace/project")
        schema_path = Path("/plugin/scripts/review-output.schema.json")
        output_path = Path("/tmp/review.json")

        command = codex_command(cwd, schema_path, output_path, "Review this scope")

        self.assertEqual(
            command,
            (
                "codex",
                "exec",
                "-C",
                "/workspace/project",
                "--skip-git-repo-check",
                "--sandbox",
                "read-only",
                "--disable",
                "hooks",
                "--ephemeral",
                "--color",
                "never",
                "--output-schema",
                "/plugin/scripts/review-output.schema.json",
                "-o",
                "/tmp/review.json",
                "Review this scope",
            ),
        )


class ReviewExecutionTest(unittest.TestCase):
    def test_main_emits_the_structured_review(self: ReviewExecutionTest) -> None:
        expected_review: ReviewDocument = {
            "findings": [],
            "summary": "No findings.",
            "residual_risks": ["Tests were not run."],
            "tests_not_run": ["unit tests"],
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            fake_codex(directory, expected_review)
            stdout = io.StringIO()
            environment = {"PATH": f"{directory}:{os.environ['PATH']}"}

            with patch.dict(os.environ, environment), contextlib.redirect_stdout(stdout):
                status = main(("--cwd", str(directory), "--scope-file", str(scope_file)))

        self.assertEqual(
            (status, stdout.getvalue().strip()),
            (0, json.dumps(expected_review)),
        )


class ReviewInputTest(unittest.TestCase):
    def test_missing_directory_reports_input_error(self: ReviewInputTest) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            missing_directory = directory / "missing-project"
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")

            completed = subprocess.run(
                (
                    sys.executable,
                    str(REVIEW_SCRIPT),
                    "--cwd",
                    str(missing_directory),
                    "--scope-file",
                    str(scope_file),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(
            (completed.returncode, completed.stderr.strip()),
            (2, f"Review directory does not exist: {missing_directory}"),
        )

    def test_missing_scope_reports_input_error(self: ReviewInputTest) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            missing_scope = directory / "missing-scope.md"

            completed = subprocess.run(
                (
                    sys.executable,
                    str(REVIEW_SCRIPT),
                    "--cwd",
                    str(directory),
                    "--scope-file",
                    str(missing_scope),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(
            (completed.returncode, completed.stderr.strip()),
            (2, f"Review scope file does not exist: {missing_scope}"),
        )

    def test_missing_rules_reports_input_error(self: ReviewInputTest) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            missing_rules = directory / "missing-rules.md"

            completed = subprocess.run(
                (
                    sys.executable,
                    str(REVIEW_SCRIPT),
                    "--cwd",
                    str(directory),
                    "--scope-file",
                    str(scope_file),
                    "--rules-file",
                    str(missing_rules),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(
            (completed.returncode, completed.stderr.strip()),
            (2, f"Review rules file does not exist: {missing_rules}"),
        )


class ReviewProtocolTest(unittest.TestCase):
    def test_invalid_review_reports_protocol_error(self: ReviewProtocolTest) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            fake_codex_output(directory, "not-json")
            environment = os.environ | {"PATH": f"{directory}:{os.environ['PATH']}"}

            completed = subprocess.run(
                (
                    sys.executable,
                    str(REVIEW_SCRIPT),
                    "--cwd",
                    str(directory),
                    "--scope-file",
                    str(scope_file),
                ),
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

        self.assertEqual(
            (completed.returncode, completed.stderr.strip()),
            (3, "Codex returned invalid review JSON."),
        )


class HookRecursionTest(unittest.TestCase):
    def test_active_hook_skips_nested_review(self: HookRecursionTest) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            executable = directory / "codex"
            executable.write_text("#!/bin/sh\nexit 7\n", encoding="utf-8")
            executable.chmod(0o755)
            environment = {
                "CODE_REVIEW_HOOK_ACTIVE": "1",
                "PATH": f"{directory}:{os.environ['PATH']}",
            }

            with patch.dict(os.environ, environment):
                status = main(("--cwd", str(directory), "--scope-file", str(scope_file)))

        self.assertEqual(status, 0)


if __name__ == "__main__":
    unittest.main()
