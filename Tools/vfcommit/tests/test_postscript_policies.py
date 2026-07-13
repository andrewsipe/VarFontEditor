"""Cross-language parity with VarFontCore PostScriptPolicyParityTests.swift."""

from __future__ import annotations

import unittest

from vfcommit_lib.name_policies import is_usable_prefix, sanitize_postscript, strip_variable_tokens

# Keep fixture strings identical to PostScriptPolicyParityTests.swift.
SANITIZE_CASES = [
    ("Milgram", "Milgram"),
    ("Loes 0.4", "Loes0.4"),
    ("Foo Bar", "FooBar"),
    ("Bad@Name", "Bad-Name"),
    ("Keep-me_ok.test?!&*", "Keep-me_ok.test?!&*"),
]

STRIP_VARIABLE_CASES = [
    ("Milgram Variable", "Milgram"),
    ("Roboto Flex", "Roboto"),
    ("Family VF", "Family"),
    ("Plain Family", "Plain Family"),
    ("", None),
]


class PostScriptPolicyParityTests(unittest.TestCase):
    def test_sanitize_postscript_parity_fixtures(self) -> None:
        for raw, expected in SANITIZE_CASES:
            with self.subTest(raw=raw):
                self.assertEqual(sanitize_postscript(raw), expected)

    def test_strip_variable_tokens_parity_fixtures(self) -> None:
        for raw, expected in STRIP_VARIABLE_CASES:
            with self.subTest(raw=raw):
                self.assertEqual(strip_variable_tokens(raw), expected)

    def test_is_usable_prefix_parity_fixtures(self) -> None:
        self.assertTrue(is_usable_prefix("Loes0.4"))
        self.assertFalse(is_usable_prefix(""))
        self.assertFalse(is_usable_prefix("Bad?"))


if __name__ == "__main__":
    unittest.main()
