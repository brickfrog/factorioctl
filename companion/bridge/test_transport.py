import unittest

import transport


class FakeRcon:
    def __init__(self, responses=None):
        self.commands = []
        self.responses = list(responses or [])

    def execute(self, command):
        self.commands.append(command)
        if self.responses:
            return self.responses.pop(0)
        return ""


class TransportTests(unittest.TestCase):
    def test_setup_surfaces_uses_mod_remote(self):
        rcon = FakeRcon(["created\n", "exists\n"])

        result = transport.setup_surfaces(rcon, ["vulcanus", "nauvis"])

        self.assertEqual(result, {"vulcanus": "created", "nauvis": "exists"})
        self.assertEqual(len(rcon.commands), 2)
        self.assertIn('remote.call("claude_interface", "ensure_surface"', rcon.commands[0])
        for command in rcon.commands:
            self.assertNotIn("game.planets", command)
            self.assertNotIn("game.surfaces", command)
            self.assertNotIn("create_surface", command)

    def test_pre_place_character_uses_mod_remote(self):
        rcon = FakeRcon(["created\n"])

        result = transport.pre_place_character(rcon, "doug-nauvis", "nauvis", spawn_offset=2)

        self.assertEqual(result, "created")
        self.assertEqual(len(rcon.commands), 1)
        command = rcon.commands[0]
        self.assertIn('remote.call("claude_interface", "pre_place_character"', command)
        self.assertIn("doug-nauvis", command)
        self.assertIn("nauvis", command)
        self.assertIn(", 15))", command)
        for forbidden in [
            "request_to_generate_chunks",
            "force_generate_chunk_requests",
            "create_entity",
            "storage.factorioctl_characters",
            "storage.factorioctl_entities",
        ]:
            self.assertNotIn(forbidden, command)


if __name__ == "__main__":
    unittest.main()
