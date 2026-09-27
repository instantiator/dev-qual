"""Tests for check_baseline.py."""

import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS_DIR))

import check_baseline


class CheckBaselineTests(unittest.TestCase):
    """Exercise the adoption-detection logic and its exit codes."""

    def run_check(self, project: Path) -> int:
        """Run check() and return its exit code."""
        return check_baseline.check(project)

    def test_adopted_via_pyproject(self) -> None:
        """pyproject.toml [tool.ruff] extend naming the baseline passes."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "pyproject.toml").write_text(
                '[tool.ruff]\nextend = "dev-qual/guidance/languages/python/tools/ruff-baseline.toml"\n'
            )
            self.assertEqual(self.run_check(project), 0)

    def test_adopted_via_ruff_toml(self) -> None:
        """A top-level ruff.toml `extend` naming the baseline passes."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "pyproject.toml").write_text('[project]\nname = "x"\n')
            (project / "ruff.toml").write_text(
                'extend = "dev-qual/guidance/languages/python/tools/ruff-baseline.toml"\n'
            )
            self.assertEqual(self.run_check(project), 0)

    def test_not_adopted_prints_relative_path(self) -> None:
        """When the baseline file is nested under the project, the suggestion is relative."""
        # Simulate dev-qual being vendored inside the consumer project: point
        # BASELINE_PATH at a synthetic file under a fake "dev-qual" subtree of
        # the temp project, and confirm the printed path is relative.
        original_baseline = check_baseline.BASELINE_PATH
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "pyproject.toml").write_text('[project]\nname = "x"\n')
            nested = (
                project
                / "dev-qual"
                / "guidance"
                / "languages"
                / "python"
                / "tools"
                / check_baseline.BASELINE_NAME
            )
            nested.parent.mkdir(parents=True)
            nested.write_text("")
            check_baseline.BASELINE_PATH = nested.resolve()
            try:
                code = self.run_check(project)
                self.assertEqual(code, 1)
                suggestion = check_baseline.suggestion_for(project)
                self.assertIn(
                    'extend = "dev-qual/guidance/languages/python/tools', suggestion
                )
            finally:
                check_baseline.BASELINE_PATH = original_baseline

    def test_not_a_python_project(self) -> None:
        """A directory with none of the marker files reports not-a-python-project, exit 0."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            self.assertEqual(self.run_check(project), 0)
            self.assertFalse(check_baseline.is_python_project(project))

    def test_absolute_path_case(self) -> None:
        """When the baseline is not nested under the project, suggest its absolute path."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "requirements.txt").write_text("requests\n")
            suggestion = check_baseline.suggestion_for(project)
            self.assertIn(str(check_baseline.BASELINE_PATH), suggestion)

    def test_malformed_toml_exits_2(self) -> None:
        """Unparseable TOML exits 2."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "pyproject.toml").write_text("[tool.ruff\nextend = broken")
            self.assertEqual(self.run_check(project), 2)


if __name__ == "__main__":
    unittest.main()
