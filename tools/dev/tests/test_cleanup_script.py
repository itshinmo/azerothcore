import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "dev" / "cleanup.sh"


class CleanupScriptTest(unittest.TestCase):
    def run_cleanup(self, *args, env=None):
        merged = os.environ.copy()
        if env:
            merged.update(env)
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
            env=merged,
        )

    def test_dry_run_is_default(self):
        result = self.run_cleanup()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("dry run:", result.stdout)
        self.assertNotIn("removed ", result.stdout)

    def test_rejects_zero_backup_keep(self):
        result = self.run_cleanup("--backups-keep", "0")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("at least 1", result.stderr)

    def test_rejects_zero_log_days(self):
        result = self.run_cleanup("--logs-days", "0")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("at least 1", result.stderr)

    def test_prune_backups_keeps_newest(self):
        with tempfile.TemporaryDirectory() as tmp:
            for stamp in ("20260101-000000", "20260102-000000", "20260103-000000"):
                (Path(tmp) / stamp).mkdir()
            result = subprocess.run(
                ["bash", "-c", 'source "$1"; DRY_RUN=0; prune_backups "$2" 2', "bash", str(SCRIPT), tmp],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertFalse((Path(tmp) / "20260101-000000").exists())
            self.assertTrue((Path(tmp) / "20260102-000000").exists())
            self.assertTrue((Path(tmp) / "20260103-000000").exists())

    def test_test_db_rejects_root(self):
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; MYSQL_ADMIN_USER=root; require_admin', "bash", str(SCRIPT)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("refusing root", result.stderr)


if __name__ == "__main__":
    unittest.main()
