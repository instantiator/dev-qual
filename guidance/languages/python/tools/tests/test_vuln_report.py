"""Tests for vuln_report.py."""

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import vuln_report

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def run_report(project: Path, input_file: Path) -> tuple[int, str]:
    """Run report() capturing stdout. Returns (exit code, stdout)."""
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        code = vuln_report.report(project, input_file)
    return code, buffer.getvalue()


class NormalizeNameTests(unittest.TestCase):
    """PEP 503 name normalisation."""

    def test_normalizes_separators_and_case(self) -> None:
        """Runs of -_. collapse to a single '-' and case is lowered."""
        self.assertEqual(
            vuln_report.normalize_name("My_Package.Thing"), "my-package-thing"
        )
        self.assertEqual(vuln_report.normalize_name("Foo--Bar"), "foo-bar")


class RankingTests(unittest.TestCase):
    """Ranking order: fix available, then direct before transitive, then name."""

    def test_ranking_order(self) -> None:
        """pkg-c (direct, fix) < pkg-b (transitive, fix) < pkg-a (no fix)."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "pyproject.toml").write_text(
                '[project]\nname = "x"\ndependencies = ["pkg-a", "pkg-c"]\n'
            )
            code, output = run_report(project, FIXTURES / "vuln_ranking.json")
            self.assertEqual(code, 1)
            lines = [line for line in output.splitlines() if line.startswith("pkg-")]
            names_in_order = [line.split()[0] for line in lines]
            self.assertEqual(names_in_order, ["pkg-c", "pkg-b", "pkg-a"])
            self.assertIn(
                "direct", next(line for line in lines if line.startswith("pkg-c"))
            )
            self.assertIn(
                "transitive", next(line for line in lines if line.startswith("pkg-b"))
            )


class DirectDetectionTests(unittest.TestCase):
    """Direct-dependency detection from pyproject.toml and requirements*.txt."""

    def test_direct_from_pyproject_with_normalization(self) -> None:
        """A pyproject dependency matches a differently-punctuated report name."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "pyproject.toml").write_text(
                '[project]\nname = "x"\ndependencies = ["My_Package.Thing>=1.0"]\n'
            )
            names = vuln_report.collect_direct_names(project)
            self.assertIn("my-package-thing", names)

    def test_direct_from_requirements_txt(self) -> None:
        """A requirements.txt entry is detected as a direct dependency."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "requirements.txt").write_text(
                "# comment\nRequests==2.0.0\n-e .\n"
            )
            names = vuln_report.collect_direct_names(project)
            self.assertIn("requests", names)


class ActionTests(unittest.TestCase):
    """Action-string generation: fix available, major bump, no fix."""

    def test_major_bump_flagged(self) -> None:
        """A fix that crosses a major version is flagged for user confirmation."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            code, output = run_report(project, FIXTURES / "vuln_major.json")
            self.assertEqual(code, 1)
            self.assertIn("MAJOR", output)
            self.assertIn("pip install 'pkg-major>=2.0.0'", output)

    def test_no_fix_available(self) -> None:
        """A vulnerability with no fix_versions recommends replacement."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            code, output = run_report(project, FIXTURES / "vuln_nofix.json")
            self.assertEqual(code, 1)
            self.assertIn("no fix available", output)
            self.assertIn("guidance/standards/dependencies.md", output)


class ExitCodeTests(unittest.TestCase):
    """Exit codes: 0 clean, 1 vulnerabilities found, 2 malformed input."""

    def test_empty_is_clean(self) -> None:
        """No dependencies with vulns exits 0."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            code, output = run_report(project, FIXTURES / "vuln_empty.json")
            self.assertEqual(code, 0)
            self.assertIn("no vulnerabilities found", output)

    def test_malformed_input_exits_2(self) -> None:
        """Invalid JSON input exits 2."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            code, _ = run_report(project, FIXTURES / "vuln_malformed.json")
            self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
