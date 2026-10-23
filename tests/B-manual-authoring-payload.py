"""Read-only closed B Source proposal fault cases; no scene I/O."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manual_payload", ROOT / "scripts/build-B-manual-authoring-payload.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ClosedPayload(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((ROOT / "rojo/source-map.json").read_text())
        self.before = json.loads((builder.OUT / "expected-before-sources.json").read_text())

    def test_complete_reviewed_graph_has_exact_eight_plus_three(self):
        payload, _ = builder.make_payload(self.manifest, self.before)
        self.assertEqual(len(payload["expectedBeforeSources"]), 168)
        self.assertEqual(set(payload["sourceChanges"]), set(builder.CHANGED))
        self.assertEqual(set(payload["newSources"]), set(builder.ADDED))
        self.assertEqual(payload["afterSourceCount"], 171)

    def test_unreviewed_old_Source_edit_is_refused(self):
        target = ROOT / "src/shared/Config/GameConfig.luau"
        def read(file):
            return builder.normalized_source(file) + ("\n-- unrelated edit" if file == target else "")
        with self.assertRaisesRegex(AssertionError, "Unreviewed retained Source edit"):
            builder.make_payload(self.manifest, self.before, read)

    def test_fog_hash_change_is_refused(self):
        path = next(iter(self.manifest["unmanaged_sources"]))
        self.manifest["unmanaged_sources"][path]["sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "Unmanaged Fog changed"):
            builder.make_payload(self.manifest, self.before)

    def test_missing_retained_or_new_source_is_refused(self):
        original = copy.deepcopy(self.manifest)
        for path in (next(iter(builder.CHANGED)), next(iter(builder.ADDED))):
            with self.subTest(path=path):
                self.manifest = copy.deepcopy(original)
                del self.manifest["variants"]["B"]["sources"][path]
                with self.assertRaises(AssertionError):
                    builder.make_payload(self.manifest, self.before)

    def test_same_count_new_paths_and_new_class_changes_are_refused(self):
        source_rows = self.manifest["variants"]["B"]["sources"]
        path = next(iter(builder.ADDED))
        original = copy.deepcopy(source_rows[path])
        source_rows[path]["class"] = "Script"
        with self.assertRaisesRegex(AssertionError, "Noncanonical new Source"):
            builder.make_payload(self.manifest, self.before)
        source_rows[path] = original
        source_rows[path + "Injected"] = source_rows.pop(path)
        with self.assertRaisesRegex(AssertionError, "Unexpected/missing Source graph"):
            builder.make_payload(self.manifest, self.before)

    def test_canonical_same_variant_file_swap_is_refused(self):
        source_rows = self.manifest["variants"]["B"]["sources"]
        first, second = list(builder.ADDED)[:2]
        source_rows[first]["file"], source_rows[second]["file"] = source_rows[second]["file"], source_rows[first]["file"]
        with self.assertRaisesRegex(AssertionError, "Noncanonical new Source"):
            builder.make_payload(self.manifest, self.before)


if __name__ == "__main__":
    unittest.main()
