import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import learning


class LearningTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.base = Path(self.tempdir.name)
        self.dir_patch = mock.patch(
            "learning._learning_dir",
            side_effect=lambda: self.base / ".factorioctl" / "learned",
        )
        self.ledger_patch = mock.patch(
            "ledger._ledger_file",
            side_effect=lambda agent_name: self.base / f".ledger-{agent_name}.json",
        )
        self.journal_patch = mock.patch(
            "journal._journal_file",
            side_effect=lambda agent_name: self.base / f".journal-{agent_name}.jsonl",
        )
        self.reflection_patch = mock.patch(
            "journal._reflection_file",
            side_effect=lambda agent_name: self.base / f".reflection-{agent_name}.json",
        )
        self.dir_patch.start()
        self.ledger_patch.start()
        self.journal_patch.start()
        self.reflection_patch.start()
        self.addCleanup(self.dir_patch.stop)
        self.addCleanup(self.ledger_patch.stop)
        self.addCleanup(self.journal_patch.stop)
        self.addCleanup(self.reflection_patch.stop)

    def test_parse_learning_trailer_extracts_structured_skill_proposal(self):
        parsed = learning.parse_learning_trailers(
            """Visible.
<skill_proposal>
name: repair_steam_power
trigger: diagnose_steam_power reports boiler_no_water or steam_engine_no_steam
preconditions:
- call diagnose_steam_power before moving entities
steps:
- fix water path before steam path
- fuel boiler
- verify power status
anti_steps:
- do not place duplicate offshore pumps
evidence:
- prior run placed a second pump beside a reusable pump
</skill_proposal>
"""
        )

        self.assertEqual(len(parsed), 1)
        proposal = parsed[0]
        self.assertEqual(proposal["kind"], "skill_proposal")
        self.assertEqual(proposal["name"], "repair_steam_power")
        self.assertIn("boiler_no_water", proposal["trigger"])
        self.assertEqual(proposal["steps"][0], "fix water path before steam path")
        self.assertEqual(proposal["anti_steps"], ["do not place duplicate offshore pumps"])

    def test_apply_learning_update_persists_pending_and_strip_hides_block(self):
        text = """Done.

<diagnostic_proposal>
name: diagnose_existing_power
problem: agent cannot tell whether a steam plant already exists
acceptance_tests:
- reports existing offshore pumps in radius
- flags boiler_no_water before suggesting rebuild
evidence:
- duplicate pump placement happened
</diagnostic_proposal>
"""

        saved = learning.apply_learning_update("doug", text)
        stripped = learning.strip_learning_trailers(text)

        self.assertEqual(stripped, "Done.")
        self.assertEqual(len(saved), 1)
        pending_files = list((self.base / ".factorioctl" / "learned" / "pending").glob("*.json"))
        self.assertEqual(pending_files, saved)
        data = json.loads(pending_files[0].read_text())
        self.assertEqual(data["status"], "pending")
        self.assertEqual(data["kind"], "diagnostic_proposal")
        self.assertEqual(data["agent"], "doug")
        self.assertIn("offshore pumps", data["acceptance_tests"][0])

    def test_finalize_reply_persists_proposal_without_showing_player(self):
        import pipe

        reply = pipe._finalize_reply(
            """Furnace repaired.

<skill_proposal>
name: repair_belt_to_furnace
trigger: drill waits for space because inserter/furnace layout is blocked
steps:
- inspect drill output tile
- move furnace footprint away from inserter tile
anti_steps:
- do not rebuild the miner first
evidence:
- drill was working but destination was blocked
</skill_proposal>
""",
            "doug",
        )

        self.assertEqual(reply, "Furnace repaired.")
        files = list((self.base / ".factorioctl" / "learned" / "pending").glob("*.json"))
        self.assertEqual(len(files), 1)
        self.assertEqual(json.loads(files[0].read_text())["name"], "repair_belt_to_furnace")

    def test_accepted_learning_renders_compactly_but_pending_stays_inert(self):
        pending = {
            "agent": "doug",
            "kind": "skill_proposal",
            "name": "pending_noise",
            "trigger": "should not be injected",
            "steps": ["do not render me"],
        }
        accepted = {
            "agent": "doug",
            "kind": "skill_proposal",
            "name": "repair_steam_power",
            "trigger": "steam plant exists but power is absent",
            "steps": [
                "call diagnose_steam_power",
                "fix water path",
                "fix steam path",
                "connect poles",
            ],
            "anti_steps": [
                "do not duplicate pumps",
                "do not trust map rocks as water",
                "do not rebuild whole plant",
            ],
        }
        learning.save_candidate(pending, status="pending")
        learning.save_candidate(accepted, status="accepted")

        rendered = learning.render_accepted_learning(learning.load_accepted_learning())

        self.assertIn("Accepted learned procedures", rendered)
        self.assertIn("repair_steam_power", rendered)
        self.assertIn("call diagnose_steam_power", rendered)
        self.assertIn("do not duplicate pumps", rendered)
        self.assertNotIn("pending_noise", rendered)
        self.assertNotIn("connect poles", rendered)
        self.assertNotIn("do not rebuild whole plant", rendered)

    def test_promote_candidate_moves_pending_to_accepted_memory(self):
        source = learning.save_candidate({
            "agent": "doug",
            "kind": "skill_proposal",
            "name": "repair_power_poles",
            "trigger": "steam engine works but lab has no power",
            "steps": ["inspect pole coverage", "connect pole chain"],
            "anti_steps": ["do not rebuild steam plant"],
        }, status="pending")

        promoted = learning.promote_candidate(source)
        rendered = learning.render_accepted_learning(learning.load_accepted_learning())

        self.assertIsNotNone(promoted)
        self.assertFalse(source.exists())
        self.assertTrue(promoted.exists())
        data = json.loads(promoted.read_text())
        self.assertEqual(data["status"], "accepted")
        self.assertIn("accepted_at", data)
        self.assertIn("repair_power_poles", rendered)
        self.assertIn("connect pole chain", rendered)

    def test_autonomy_prompt_includes_accepted_learning_and_proposal_instruction(self):
        import pipe

        learning.save_candidate({
            "agent": "doug",
            "kind": "skill_proposal",
            "name": "repair_steam_power",
            "trigger": "diagnose_steam_power reports no steam",
            "steps": ["repair water first"],
            "anti_steps": ["avoid duplicate pumps"],
        }, status="accepted")
        learning.save_candidate({
            "agent": "doug",
            "kind": "skill_proposal",
            "name": "pending_noise",
            "trigger": "not accepted",
            "steps": ["should stay hidden"],
        }, status="pending")

        class StubRCON:
            def execute(self, _cmd):
                return ""

        thread = pipe.AgentThread.__new__(pipe.AgentThread)
        thread.agent_name = "doug"
        thread.rcon = StubRCON()
        thread._exec_ticks_since_plan = 5
        thread._planner_interval = 5
        thread._planner_model = None
        thread._reflect_interval = 16

        prompt = thread._compose_autonomy_prompt()

        self.assertIn("Accepted learned procedures", prompt)
        self.assertIn("repair_steam_power", prompt)
        self.assertIn("avoid duplicate pumps", prompt)
        self.assertIn("<skill_proposal>", prompt)
        self.assertNotIn("pending_noise", prompt)


if __name__ == "__main__":
    unittest.main()
