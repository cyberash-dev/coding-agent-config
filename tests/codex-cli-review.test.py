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


def fake_codex(
    directory: Path, review: ReviewDocument, home_record: Path | None = None
) -> Path:
    return fake_codex_output(directory, json.dumps(review), home_record)


def fake_codex_output(directory: Path, output: str, home_record: Path | None = None) -> Path:
    executable = directory / "codex"
    executable.write_text(
        """#!/usr/bin/env python3
import os
import pathlib
import sys

output_path = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
output_path.write_text(%r, encoding="utf-8")
home_record = %r
if home_record is not None:
    pathlib.Path(home_record).write_text(os.environ.get("CODEX_HOME", ""), encoding="utf-8")
"""
        % (output, None if home_record is None else str(home_record)),
        encoding="utf-8",
    )
    executable.chmod(0o755)
    return executable


def review_output_with_stdin_held_open(
    scope_file: Path, environment: dict[str, str], timeout: float = 15.0
) -> str:
    with subprocess.Popen(
        (
            sys.executable,
            str(REVIEW_SCRIPT),
            "--cwd",
            str(scope_file.parent),
            "--scope-file",
            str(scope_file),
        ),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    ) as review:
        try:
            review.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            review.kill()
            raise
        return review.stdout.read() if review.stdout else ""


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

        command = codex_command(cwd, schema_path, output_path, "Review this scope", None)

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

    def test_command_pins_the_review_model(self: CodexCommandTest) -> None:
        command = codex_command(
            Path("/workspace/project"),
            Path("/plugin/scripts/review-output.schema.json"),
            Path("/tmp/review.json"),
            "Review this scope",
            "gpt-5.6-luna",
        )

        self.assertEqual(command[:4], ("codex", "exec", "-m", "gpt-5.6-luna"))


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


class ReviewHomeTest(unittest.TestCase):
    def review_home_of(self: ReviewHomeTest, agent_home: Path) -> Path:
        return agent_home / ".cache" / "coding-agent-config" / "codex-review-home"

    def test_review_runs_in_the_prepared_review_home(self: ReviewHomeTest) -> None:
        review: ReviewDocument = {
            "findings": [],
            "summary": "No findings.",
            "residual_risks": [],
            "tests_not_run": [],
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            agent_home = directory / "home"
            operator_home = agent_home / ".codex"
            operator_home.mkdir(parents=True)
            (operator_home / "auth.json").write_text("{}", encoding="utf-8")
            prepared_home = self.review_home_of(agent_home)
            prepared_home.mkdir(parents=True)
            (prepared_home / "config.toml").write_text('model = "x"', encoding="utf-8")
            (prepared_home / "auth.json").symlink_to(operator_home / "auth.json")
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            home_record = directory / "codex-home"
            fake_codex(directory, review, home_record)
            environment = {
                "HOME": str(agent_home),
                "CODEX_HOME": str(operator_home),
                "PATH": f"{directory}:{os.environ['PATH']}",
            }

            with patch.dict(os.environ, environment), contextlib.redirect_stdout(io.StringIO()):
                main(("--cwd", str(directory), "--scope-file", str(scope_file)))
            codex_home = home_record.read_text(encoding="utf-8")

        self.assertEqual(codex_home, str(prepared_home))

    def test_review_keeps_the_operator_home_when_none_is_prepared(self: ReviewHomeTest) -> None:
        review: ReviewDocument = {
            "findings": [],
            "summary": "No findings.",
            "residual_risks": [],
            "tests_not_run": [],
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            agent_home = directory / "home"
            agent_home.mkdir()
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            home_record = directory / "codex-home"
            fake_codex(directory, review, home_record)
            environment = {
                "HOME": str(agent_home),
                "CODEX_HOME": str(directory / "operator-codex"),
                "PATH": f"{directory}:{os.environ['PATH']}",
            }

            with patch.dict(os.environ, environment), contextlib.redirect_stdout(io.StringIO()):
                main(("--cwd", str(directory), "--scope-file", str(scope_file)))
            codex_home = home_record.read_text(encoding="utf-8")
            operator_home = str(directory / "operator-codex")

        self.assertEqual(codex_home, operator_home)

    def test_review_keeps_the_operator_home_when_the_login_is_not_shared(
        self: ReviewHomeTest,
    ) -> None:
        """An operator whose OAuth tokens live in the OS keyring has no
        auth.json to share, and the trimmed home would carry no credentials at
        all. The expensive home that works beats the cheap one that cannot
        sign in.
        """
        review: ReviewDocument = {
            "findings": [],
            "summary": "No findings.",
            "residual_risks": [],
            "tests_not_run": [],
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            agent_home = directory / "home"
            prepared_home = self.review_home_of(agent_home)
            prepared_home.mkdir(parents=True)
            (prepared_home / "config.toml").write_text('model = "x"', encoding="utf-8")
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            home_record = directory / "codex-home"
            fake_codex(directory, review, home_record)
            environment = {
                "HOME": str(agent_home),
                "CODEX_HOME": str(directory / "operator-codex"),
                "PATH": f"{directory}:{os.environ['PATH']}",
            }

            with patch.dict(os.environ, environment), contextlib.redirect_stdout(io.StringIO()):
                main(("--cwd", str(directory), "--scope-file", str(scope_file)))
            codex_home = home_record.read_text(encoding="utf-8")
            operator_home = str(directory / "operator-codex")

        self.assertEqual(codex_home, operator_home)
    def test_review_keeps_a_codex_home_the_shared_login_does_not_belong_to(
        self: ReviewHomeTest,
    ) -> None:
        """The prepared login points at the home the install ran against. A
        CODEX_HOME switched since then selects another account, and the review
        has to follow the caller rather than sign in as the installer.
        """
        review: ReviewDocument = {
            "findings": [],
            "summary": "No findings.",
            "residual_risks": [],
            "tests_not_run": [],
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            agent_home = directory / "home"
            installed_home = directory / "codex-installed"
            installed_home.mkdir(parents=True)
            (installed_home / "auth.json").write_text("{}", encoding="utf-8")
            selected_home = directory / "codex-selected"
            selected_home.mkdir(parents=True)
            (selected_home / "auth.json").write_text("{}", encoding="utf-8")
            prepared_home = self.review_home_of(agent_home)
            prepared_home.mkdir(parents=True)
            (prepared_home / "config.toml").write_text('model = "x"', encoding="utf-8")
            (prepared_home / "auth.json").symlink_to(installed_home / "auth.json")
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            home_record = directory / "codex-home"
            fake_codex(directory, review, home_record)
            environment = {
                "HOME": str(agent_home),
                "CODEX_HOME": str(selected_home),
                "PATH": f"{directory}:{os.environ['PATH']}",
            }

            with patch.dict(os.environ, environment), contextlib.redirect_stdout(io.StringIO()):
                main(("--cwd", str(directory), "--scope-file", str(scope_file)))
            codex_home = home_record.read_text(encoding="utf-8")

        self.assertEqual(codex_home, str(selected_home))

class ReviewStdinTest(unittest.TestCase):
    def test_review_does_not_wait_on_the_caller_stdin(self: ReviewStdinTest) -> None:
        """`codex exec` reads a piped stdin to EOF and appends it to the prompt.

        A caller that holds its own stdin open would hang the review for the
        whole of its timeout and pay for nothing.
        """
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            scope_file = directory / "scope.md"
            scope_file.write_text("Review src/payment.py.", encoding="utf-8")
            executable = directory / "codex"
            executable.write_text(
                "#!/usr/bin/env python3\n"
                "import pathlib, sys\n"
                "sys.stdin.read()\n"
                'pathlib.Path(sys.argv[sys.argv.index("-o") + 1]).write_text(\n'
                '    \'{"findings": [], "summary": "s", "residual_risks": [], "tests_not_run": []}\',\n'
                '    encoding="utf-8",\n'
                ")\n",
                encoding="utf-8",
            )
            executable.chmod(0o755)
            # The guard would return before the child ever starts, and the test
            # would pass on unfixed code.
            environment = {
                key: value
                for key, value in os.environ.items()
                if key != "CODE_REVIEW_HOOK_ACTIVE"
            }
            environment["PATH"] = f"{directory}:{os.environ['PATH']}"

            emitted = review_output_with_stdin_held_open(scope_file, environment)

        self.assertEqual(json.loads(emitted)["summary"], "s")

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
