# Manual B authoring preservation support

This folder begins from the accepted, author-saved B at commit
`2d3ccd7044f832221e616d7a09ec8c8ce36e4e68`. `baseline.json` records exact
A/B/C bytes and SHA256, the committed Rojo map hash, and all 168 expected
B Sources. The 165 canonical Sources are read from that Git commit and match
the accepted mapping. The three unmanaged Fog hashes independently match the
previous night-toggle guard. This prevents another agent's concurrent runtime
module edits from silently redefining the before-state.

`before-manual-authoring.zip` contains one entry,
`B-before-manual-authoring.rbxl`: exactly 1,759,554 bytes, SHA256
`c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f`.
ZIP SHA256: `cd2b0a34b50b31693aa1911d958805ba0e0ed5d1230940a01477365feda80682`.
The build helper refuses to replace differing existing support files.

## Native snapshot API

`native-snapshot.luau` returns `function(options)`. Its property inventory,
encoder, persistent service scope, Terrain material palette and script editor
buffer reads are unchanged from the green-variants snapshot. Only owner,
default expected Source count and owned memory key prefix change.

```luau
local snapshot = assert(loadstring(snapshotSource))()
local before = snapshot({
    sourceCount = 168,
    storeKey = "__CornBManualAuthoringV1_before",
    compact = true,
})
```

The key prefix is exactly `__CornBManualAuthoringV1_` (25 characters).
`compact=true` omits `nodes` from the returned copy; the full result remains
at the optional owned `_G` key. Without `storeKey` the callable does not write
to `_G`. Each node has its stable native identity, parent identity, class,
real name, path and independent property/attribute/tag/Source hashes.
The root agent owns native execution and eventual cleanup of the owned table.
No native execution occurred while preparing this support folder.

## Strict future author Save audit

Create a **new** audit for this change from the frozen ZIP. Do not call the old
green-variants or night-toggle audit against a new authoring scene: their
allowlists intentionally reject the requested map authoring changes.

Reusable read-only helpers are exposed by
`scripts/verify-B-green-variants-copy.py` and its imported preservation helpers:
`r.p.known_dom(path)`, `r.p.unknown_properties(path)`, `r.validate_unknown`,
`identity`, `scalar`, `remap_refs`, `same`, `expected_same`,
`attributes_same`, and `tags_same`.
The native property snapshot is complementary evidence; it does not read raw
Terrain grids, hidden binary mesh payloads or engine-generated metadata.

Before installation, freeze and explicitly pin an independent payload and plan:

```json
{
  "owner": "CornBManualAuthoringV1",
  "baseline_sha256": "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f",
  "source_changes": [{"uid": "retained stable ID", "path": "old path", "before_sha256": "...", "after_sha256": "..."}],
  "retained_changes": [{"uid": "...", "property": "...", "before": ["type", "text", []], "after": ["type", "text", []]}],
  "retained_moves": [{"uid": "...", "old_parent_uid": "...", "new_parent_path": "explicit new group"}],
  "new_nodes": {"explicit final path": {"class": "...", "properties": {"complete saved DOM excluding generated metadata": "..."}}}
}
```

Match retained objects by nonzero UniqueId, then validate exact class and real
Name. Require every original identity to survive exactly once. Canonicalize
exporter suffixes and all Ref-valued properties through the identity map.
Permit a retained parent change only for the exact identity and destination
declared in `retained_moves`; an entire subtree rename or broad group-root
exception would hide unrelated changes. The existing `canonicalize` helper
requires unchanged parents and therefore needs a narrowly scoped extension for
this authoring task if grouping retains existing world objects.

For each of the 6,054 original saved objects, preserve the complete property
schema and every exact value unless a frozen row declares the precise change.
This includes all 168 old Sources (except exact reviewed replacement bytes),
Fog, Lighting, settings, art, physics, references, mesh metadata, attributes,
tags and both retained identity fields. Plan construction must use baseline
data plus the independently reviewed installer proposal, never learn allowed
values from the candidate Save.

New code, markers, groups and corn must match the full declared DOM and exact
node set. Permit only fresh, valid generated UniqueId/HistoryId/ScriptGuid;
require global identity and ScriptGuid uniqueness. Freeze actual normal engine
defaults using an already accepted same-class prototype or a separately reviewed
read-only native property proposal. Added static session mesh content can save
as `None`; that fact must be explicitly described and precisely allowed if it
applies, with its deterministic reconstruction contract independently checked.

Unchanged known raw binary properties and the unknown Terrain payload must
remain byte-identical. Preserve the existing narrow finite Camera/Focus and
FilteredSelection metadata exceptions. Rehash every input at audit exit and
require A/C hashes unchanged. Never refresh scene hashes in the Rojo manifest
until the new strict audit reports `passed:true, complete:true`.

Useful negative fixtures: missing/extra corn, moved unrelated world node,
retained UID replacement, bad group parent, a marker added outside the proposal,
wrong Source, changed Source attributes, Lighting/Fog delta, hidden mesh metadata
delta, raw Terrain delta, reused new IDs/ScriptGuid and a candidate-derived plan.
Positive fixtures should cover exporter suffix reindexing, exact declared group
moves with valid references, and the existing finite editor Camera exception.

This support work did not open or mutate Studio, serialize or rewrite any
scene, perform Save, modify production files or manifests, commit, push or
publish assets.
