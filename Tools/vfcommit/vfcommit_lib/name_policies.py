"""PostScript and variable-token helpers.

Canonical rules live in VarFontCore ``PostScriptNaming.swift`` — keep this module in sync.

Rules:
- **sanitize_postscript:** remove spaces, then replace any character outside
  ``A-Za-z0-9 - . _ ? ! & *`` with ``-``.
- **strip_variable_tokens:** remove whole-word ``Variable`` / ``VF`` / ``GX`` / ``Flex``
  (case-insensitive), then boundary-delimited suffix forms such as ``-Variable``, ``-VF``,
  `` VariableItalic``, etc.
- **is_usable_prefix:** reject empty strings and any value containing ``?``.
"""

from __future__ import annotations

import re

from vfcommit_lib.string_utils import is_empty, normalize_empty

# Mirrors PostScriptNaming.stripVariableTokens in Swift.
RE_VARIABLE_TOKENS = re.compile(r"\b(Variable|VF|GX|Flex)\b", re.I)
RE_VARIABLE_BOUNDARY = re.compile(r"(?i)(?:^|[-_\s])Variable(?:Italic)?(?=$|[-_\s])")
RE_VF_GX_FLEX_BOUNDARY = re.compile(r"(?i)(?:^|[-_\s])(VF|GX|Flex)(?=$|[-_\s])")
# Mirrors PostScriptNaming.sanitizePostscript in Swift.
RE_SANITIZE_POSTSCRIPT = re.compile(r"[^A-Za-z0-9\-\._\?\!\&\*]")


def is_usable_prefix(value: str | None) -> bool:
    """Reject empty strings and placeholder ``?`` values before prefix inference."""
    if is_empty(value):
        return False
    return "?" not in str(value)


def sanitize_postscript(name: str) -> str:
    """Sanitize PostScript-like names for fvar instance strings."""
    name = name.replace(" ", "")
    return RE_SANITIZE_POSTSCRIPT.sub("-", name)


def strip_variable_tokens(text: str | None) -> str | None:
    """Strip Variable/VF/GX/Flex tokens from family-like strings."""
    text = normalize_empty(text)
    if is_empty(text):
        return None

    s = str(text)
    s, _ = RE_VARIABLE_TOKENS.subn("", s)
    s = RE_VARIABLE_BOUNDARY.sub(" ", s)
    s = RE_VF_GX_FLEX_BOUNDARY.sub(" ", s)
    return normalize_empty(s)
