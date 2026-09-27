"""Tests for ruff-baseline.toml: structure, and (if ruff is installed) live linting."""

import shutil
import subprocess
import unittest
from pathlib import Path
from typing import Any

import tomllib

TOOLS_DIR = Path(__file__).resolve().parent.parent
BASELINE = TOOLS_DIR / "ruff-baseline.toml"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "ruff_violations.py"


class BaselineStructureTests(unittest.TestCase):
    """The baseline file parses and declares the required rules and thresholds."""

    data: dict[str, Any]

    @classmethod
    def setUpClass(cls) -> None:
        """Parse the baseline once for all structure assertions."""
        with BASELINE.open("rb") as handle:
            cls.data = tomllib.load(handle)

    def test_extend_select_has_required_codes(self) -> None:
        """extend-select includes every rule prefix the plan requires."""
        codes = self.data["lint"]["extend-select"]
        for required in (
            "ANN",
            "ANN401",
            "BLE001",
            "S110",
            "E722",
            "B006",
            "PTH",
            "C901",
            "PLR0913",
            "UP",
        ):
            self.assertIn(required, codes)

    def test_thresholds(self) -> None:
        """mccabe and pylint thresholds match the plan's limits."""
        self.assertEqual(self.data["lint"]["mccabe"]["max-complexity"], 10)
        self.assertEqual(self.data["lint"]["pylint"]["max-args"], 4)

    def test_per_file_ignores_for_tests(self) -> None:
        """Test files are exempt from ANN and PLR0913."""
        ignores = self.data["lint"]["per-file-ignores"]
        self.assertEqual(set(ignores["**/tests/**"]), {"ANN", "PLR0913"})
        self.assertEqual(set(ignores["**/test_*.py"]), {"ANN", "PLR0913"})

    def test_uses_extend_select_not_select(self) -> None:
        """The baseline avoids lint.select so it composes into any project's config."""
        self.assertNotIn("select", self.data["lint"])


class BaselineLiveLintTests(unittest.TestCase):
    """If ruff is installed, the baseline actually catches the violations it targets."""

    def test_ruff_reports_bare_except_and_mutable_default(self) -> None:
        """ruff check --config <baseline> flags E722 and B006 on the fixture."""
        if shutil.which("ruff") is None:
            self.skipTest("ruff is not installed")
        result = subprocess.run(
            [
                "ruff",
                "check",
                "--config",
                str(BASELINE),
                "--no-cache",
                str(FIXTURE),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertIn("E722", result.stdout)
        self.assertIn("B006", result.stdout)


if __name__ == "__main__":
    unittest.main()
