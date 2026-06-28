import tempfile
import unittest
from pathlib import Path
from unittest import mock

import journal


class JournalTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.base = Path(self.tempdir.name)
        self.journal_patch = mock.patch(
            "journal._journal_file",
            side_effect=lambda agent_name: self.base / f".journal-{agent_name}.jsonl",
        )
        self.reflection_patch = mock.patch(
            "journal._reflection_file",
            side_effect=lambda agent_name: self.base / f".reflection-{agent_name}.json",
        )
        self.journal_patch.start()
        self.reflection_patch.start()
        self.addCleanup(self.journal_patch.stop)
        self.addCleanup(self.reflection_patch.stop)

    def test_append_event_loads_recent_events_in_file_order_and_respects_limit(self):
        journal.append_event("doug", "discovery", "Found copper east of spawn")
        journal.append_event("doug", "unknown", "Fallback kind is progress")
        journal.append_event("doug", "milestone", "Starter power is online")

        events = journal.load_events("doug", limit=2)

        self.assertEqual([event["kind"] for event in events], ["progress", "milestone"])
        self.assertEqual(
            [event["text"] for event in events],
            ["Fallback kind is progress", "Starter power is online"],
        )
        self.assertTrue(all(event["ts"] for event in events))
        self.assertEqual(journal.count_events("doug"), 3)

    def test_load_events_and_reflection_are_total_for_missing_and_corrupt_files(self):
        self.assertEqual(journal.load_events("doug"), [])
        self.assertEqual(journal.load_reflection("doug"), journal.default_reflection())

        (self.base / ".journal-doug.jsonl").write_text(
            '{"ts": "ok", "kind": "progress", "text": "good"}\n'
            "{not json\n"
            '{"ts": null, "kind": 3, "text": ["coerced"]}\n'
        )
        (self.base / ".reflection-doug.json").write_text("{not json")

        self.assertEqual(len(journal.load_events("doug")), 2)
        self.assertEqual(journal.load_reflection("doug"), journal.default_reflection())

    def test_should_reflect_only_at_positive_interval_multiples(self):
        self.assertFalse(journal.should_reflect(0, interval=16))
        self.assertFalse(journal.should_reflect(15, interval=16))
        self.assertTrue(journal.should_reflect(16, interval=16))
        self.assertTrue(journal.should_reflect(32, interval=16))
        self.assertFalse(journal.should_reflect(16, interval=0))

    def test_parse_reflection_extracts_two_buckets_and_tolerates_partial_blocks(self):
        parsed = journal.parse_reflection(
            """Visible text.
<reflection>
structures:
- Smelting line west of spawn
- Labs near the bus
error_tips:
- Verify inserter direction after placement
- Check power before expanding
</reflection>
"""
        )

        self.assertEqual(
            parsed["structures"],
            ["Smelting line west of spawn", "Labs near the bus"],
        )
        self.assertEqual(
            parsed["error_tips"],
            ["Verify inserter direction after placement", "Check power before expanding"],
        )
        self.assertIsNone(journal.parse_reflection("No reflection here."))
        self.assertEqual(
            journal.parse_reflection("<reflection>\nerror_tips:\n- Avoid dead belts\n</reflection>"),
            {"error_tips": ["Avoid dead belts"]},
        )

    def test_apply_reflection_update_replaces_persists_and_strip_is_idempotent(self):
        journal.apply_reflection_update(
            "doug",
            "<reflection>\nstructures:\n- Old base\nerror_tips:\n- Old tip\n</reflection>",
        )

        updated = journal.apply_reflection_update(
            "doug",
            "Done.\n<reflection>\nstructures:\n- New mall\nerror_tips:\n- New tip\n</reflection>",
        )

        self.assertEqual(updated["structures"], ["New mall"])
        self.assertEqual(updated["error_tips"], ["New tip"])
        self.assertTrue(updated["updated_at"])
        self.assertEqual(journal.load_reflection("doug")["structures"], ["New mall"])

        text = "Before.\n\n<reflection>\nerror_tips:\n- Hidden\n</reflection>\n\nAfter."
        self.assertEqual(journal.strip_reflection_trailer(text), "Before.\n\nAfter.")
        self.assertEqual(
            journal.strip_reflection_trailer(journal.strip_reflection_trailer(text)),
            "Before.\n\nAfter.",
        )

    def test_render_memory_empty_and_populated(self):
        self.assertEqual(journal.render_memory([], journal.default_reflection()), "")

        rendered = journal.render_memory(
            [{"kind": "failure", "text": "Inserter faced the wrong way"}],
            {
                "structures": ["Iron smelter at spawn"],
                "error_tips": ["Use rotate_entity after placement"],
                "updated_at": "now",
            },
        )

        self.assertIn("Recent events:", rendered)
        self.assertIn("failure: Inserter faced the wrong way", rendered)
        self.assertIn("EXISTING STRUCTURES", rendered)
        self.assertIn("Iron smelter at spawn", rendered)
        self.assertIn("ERROR TIPS", rendered)
        self.assertIn("Use rotate_entity after placement", rendered)

    def test_finalize_reply_applies_reflection_and_journals_ledger_progress(self):
        import pipe

        finalized = pipe._finalize_reply(
            """I placed the first drill.
<ledger>
progress: Placed the first drill
</ledger>
<reflection>
structures:
- Drill on the northern iron patch
error_tips:
- Check fuel after placing burner drills
</reflection>
""",
            "doug",
        )

        self.assertEqual(finalized, "I placed the first drill.")
        self.assertEqual(
            journal.load_reflection("doug")["structures"],
            ["Drill on the northern iron patch"],
        )
        self.assertEqual(journal.load_events("doug")[-1]["text"], "Placed the first drill")

    def test_autonomy_tick_injects_memory_and_periodic_reflection_nudge(self):
        import ledger
        import pipe

        ledger_patch = mock.patch(
            "ledger._ledger_file",
            side_effect=lambda agent_name: self.base / f".ledger-{agent_name}.json",
        )
        ledger_patch.start()
        self.addCleanup(ledger_patch.stop)
        ledger.save_ledger("doug", {
            "objective": "Build starter power",
            "plan_steps": ["Place boiler"],
            "progress_notes": [],
            "updated_at": "now",
        })
        for i in range(2):
            journal.append_event("doug", "failure", f"failure {i}")
        journal.save_reflection("doug", {
            "structures": ["Boiler area near water"],
            "error_tips": ["Confirm offshore pump water connection"],
            "updated_at": "now",
        })

        class StubRCON:
            def execute(self, _cmd):
                return ""

        thread = pipe.AgentThread.__new__(pipe.AgentThread)
        thread.agent_name = "doug"
        thread.rcon = StubRCON()
        thread._exec_ticks_since_plan = 0
        thread._planner_interval = 5
        thread._planner_model = None
        thread._reflect_interval = 2

        prompt = thread._compose_autonomy_prompt()

        self.assertIn("failure: failure 1", prompt)
        self.assertIn("Boiler area near water", prompt)
        self.assertIn("ERROR TIPS", prompt)
        self.assertIn("<reflection>", prompt)
        self.assertIn("what is built where", prompt)


if __name__ == "__main__":
    unittest.main()
