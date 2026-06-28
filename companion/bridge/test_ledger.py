import importlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import ledger


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.base = Path(self.tempdir.name)
        self.file_patch = mock.patch(
            "ledger._ledger_file",
            side_effect=lambda agent_name: self.base / f".ledger-{agent_name}.json",
        )
        self.file_patch.start()
        self.addCleanup(self.file_patch.stop)

    def test_parse_well_formed_ledger_trailer(self):
        text = """Done.
<ledger>
objective: Build iron automation
plan:
- Mine iron ore
- Feed a furnace
progress: Placed the first drill
</ledger>
"""

        parsed = ledger.parse_ledger_trailer(text)

        self.assertEqual(parsed["objective"], "Build iron automation")
        self.assertEqual(parsed["plan_steps"], ["Mine iron ore", "Feed a furnace"])
        self.assertEqual(parsed["progress"], "Placed the first drill")

    def test_parse_returns_none_without_ledger_block(self):
        self.assertIsNone(ledger.parse_ledger_trailer("Plain narration only."))

    def test_parse_tolerates_missing_keys(self):
        parsed = ledger.parse_ledger_trailer("<ledger>\nprogress: Checked the belt.\n</ledger>")

        self.assertEqual(parsed, {"progress": "Checked the belt."})

    def test_load_returns_default_for_missing_and_corrupt_file(self):
        self.assertEqual(ledger.load_ledger("doug"), ledger.default_ledger())

        (self.base / ".ledger-doug.json").write_text("{not json")

        self.assertEqual(ledger.load_ledger("doug"), ledger.default_ledger())

    def test_save_then_load_round_trips(self):
        saved = {
            "objective": "Automate copper",
            "plan_steps": ["Place miner", "Place furnace"],
            "progress_notes": ["Found copper patch"],
            "updated_at": "2026-06-27T12:00:00",
        }

        ledger.save_ledger("doug", saved)

        self.assertEqual(ledger.load_ledger("doug"), saved)
        self.assertTrue((self.base / ".ledger-doug.json").read_text().endswith("\n"))

    def test_apply_update_replaces_plan_for_new_objective_and_caps_progress(self):
        for i in range(11):
            ledger.apply_ledger_update(
                "doug",
                f"<ledger>\nprogress: progress {i}\n</ledger>",
            )

        updated = ledger.apply_ledger_update(
            "doug",
            """<ledger>
objective: Build starter science
plan:
- Feed labs
- Craft red science
progress: Started the science plan
</ledger>""",
        )

        self.assertEqual(updated["objective"], "Build starter science")
        self.assertEqual(updated["plan_steps"], ["Feed labs", "Craft red science"])
        self.assertEqual(len(updated["progress_notes"]), 10)
        self.assertEqual(updated["progress_notes"][0], "progress 2")
        self.assertEqual(updated["progress_notes"][-1], "Started the science plan")
        self.assertTrue(updated["updated_at"])

    def test_strip_ledger_trailer_removes_block_and_keeps_narration(self):
        text = "Before.\n\n<ledger>\nprogress: Hidden\n</ledger>\n\nAfter."

        stripped = ledger.strip_ledger_trailer(text)

        self.assertEqual(stripped, "Before.\n\nAfter.")
        self.assertEqual(ledger.strip_ledger_trailer("No trailer."), "No trailer.")

    def test_render_ledger_empty_and_with_objective(self):
        self.assertEqual(ledger.render_ledger(ledger.default_ledger()), "")

        rendered = ledger.render_ledger({
            "objective": "Repair power",
            "plan_steps": ["Find break", "Replace pole"],
            "progress_notes": ["Reached the blackout area"],
            "updated_at": "now",
        })

        self.assertIn("Repair power", rendered)
        self.assertIn("1. Find break", rendered)
        self.assertIn("Reached the blackout area", rendered)

    def test_autonomy_prompt_continuity_and_ledger_protocol(self):
        pipe = importlib.import_module("pipe")

        self.assertNotIn("check your current situation", pipe.AUTONOMY_PROMPT)
        self.assertIn("continuity", pipe.AUTONOMY_PROMPT.lower())
        self.assertIn("<ledger>", pipe.AUTONOMY_PROMPT)


if __name__ == "__main__":
    unittest.main()
