# Finishing in Final Cut Pro

One measured timeline, two finishes. Both start from the same `demo/timeline.json`, so the
cut is decided once — by the narration and the measured clips — and only the finish differs.

| | Remotion | Final Cut Pro |
|---|---|---|
| Render | one command, headless | a person presses Share |
| After the app changes | re-capture, re-render | re-export, re-import, **redo every hand edit** |
| Titles, transitions, effects | `demo/studio/src/lib/theme.ts` and components | Installed Apple and motionVFX Motion templates |
| Captions | styled, burned in | FCP caption roles |
| Fine-tuning | edit code | direct manipulation — FCP is better at this |
| Review by Claude | frames from the render | frames from the exported file |

Remotion is the default because it closes the loop without a person. Choose the FCP finish
when titles, lower thirds or hand-tuned pacing matter more than re-rendering for free.

## Commands

```bash
node ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile.mjs --project .
node ${CLAUDE_PLUGIN_ROOT}/scripts/timeline-to-fcpxml.mjs --project .      # -> demo/out/demo.fcpxml
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-finish-manifest.mjs --project .   # auditable handoff
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-templates.mjs                        # honest local inventory
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-templates.mjs --provider motionvfx --downloaded --list
```

The export picks the newest FCPXML version the installed FCP imports and validates the file
against **that app's own DTD** (`Interchange.framework/…/FCPXMLv1_NN.dtd`) with `xmllint`. An
invalid file exits non-zero and is never handed to FCP.

If native Motion design is part of the approved finish, set `meta.authoritativeRenderer` to
`final-cut-pro`. The Remotion movie remains useful for timing and footage review, but it is a
proxy for native titles, logos, transitions, and effects and must not satisfy the final review gate.

## Choosing the look

```json
"fcp": {
  "titleTemplate": "DFPT",
  "lowerThirdTemplate": "51PI",
  "transitionTemplate": "6FF7",
  "captionLanguage": "en",
  "projectName": "Product demo",
  "version": "1.14"
}
```

- Selectors come from `fcp-templates.mjs`: full uid, `Category/Name`, exact name, or a
  motionVFX four-character token. Prefer the token because names such as `Title` are ambiguous.
- `meta.fcp.transitionTemplate` applies one downloaded Motion transition to every non-cut edit.
  Override one edit with `sections[].transitionIn.fcpTemplate`.
- Apply a downloaded Motion effect to one captured or still section with
  `sections[].fcp.effectTemplate`.
- A title that is missing falls back to Basic Title/Basic Lower Third with a note. Missing
  transitions and effects are ignored with a note. A motionVFX catalog placeholder is reported
  explicitly; download it in mExtension before exporting again.
- The template's own styling is kept: the export writes the text and nothing else, so the
  look is the template's.

Example per-section choices:

```json
{
  "transitionIn": { "kind": "crossfade", "seconds": 0.4, "fcpTemplate": "6FF7" },
  "fcp": { "effectTemplate": "2YRR" }
}
```

## motionVFX: inventory, previews, and selection

mExtension exposes its large catalog inside Final Cut with symlinks to `.mExt-Placeholders`.
Those are discoverable catalog entries, not installed template payloads. The inventory records
both states, while the exporter resolves **downloaded only**.

```bash
# Counts by kind, provider, and real availability — no network needed
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-templates.mjs

# Search only usable motionVFX assets
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-templates.mjs \
  --provider motionvfx --downloaded --kind title --find "lower third" --limit 20 --list

# Public motionVFX preview metadata for a shortlisted token
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-templates.mjs \
  --token 51PI --downloaded --previews --json

# Current official collection membership and local coverage (network; slower)
node ${CLAUDE_PLUGIN_ROOT}/scripts/fcp-templates.mjs \
  --provider motionvfx --collections --json

# Download real preview media for visual inspection; maximum 12 candidates per pass
preview_dir=$(mktemp -d /tmp/demo-motionvfx.XXXXXX)
node ${CLAUDE_PLUGIN_ROOT}/scripts/motionvfx-previews.mjs \
  --tokens 51PI,6RRA,6FF7 --out "$preview_dir"
```

Use the downloaded stills for a first-pass contact sheet, then inspect frames across each video,
not merely its opening frame. Preview clips vary in duration; the materializer measures the real
video duration with `ffprobe` and records it in `manifest.json`.

Evaluate a shortlist against the edit:

- **Readability:** real copy must fit at delivery resolution and stay inside title-safe margins.
- **Footage compatibility:** overlays must preserve the product UI and its focal action; avoid
  transitions that obscure an important before/after state.
- **Pacing:** a transition should normally resolve inside 0.3–0.5s. An elaborate intro earns
  time only at the opening or a genuine chapter break.
- **Coherence:** prefer one motionVFX family for title, lower third, and transition. Mixing several
  visual dialects makes a short product demo look assembled from templates.
- **Restraint:** one purposeful effect is stronger than stacking an effect, animated overlay,
  camera zoom, and kinetic caption on the same shot.

Generators, backgrounds, infographic modules, and overlays are inventoried and previewable too,
but their drop zones and published parameters differ per template. Place and tune those by hand in
FCP after import; do not pretend the generic FCPXML exporter populated template-specific controls.

## Native binding probe and evidence

Treat a template reference as an instruction to finish, not as proof that a title is complete.
Before importing a whole cut, make a short disposable probe in Final Cut Pro with sentinel text,
one real logo, and representative light and dark footage. Confirm a warning-free import and a
short native export. For every title family, inspect entrance, settled hold, and exit frames at
delivery resolution. Verify every media well has a real source, unused fields are cleared, the
complete logo stays visible, and contrast, safe placement, and readable dwell work with the longest
final copy. Record controls that do not round-trip in `fcp-finish-manifest.json`.

DTD validity is necessary but not sufficient: treat every FCP import warning or invalid-edit
message as a failed test until understood. Keep the finished native library as the authoritative
editable deliverable when FCPXML cannot preserve a media-well assignment; do not overwrite it by
re-importing the XML.

## What the export contains

```
primary storyline   one gap, the length of the video
  lane  3           captions (iTT, meta.fcp.captionLanguage)
  lane  2           lower thirds (onScreenText)
  lane  1           connected storyline: clips, title cards, cross dissolves
  lane -1           narration, role dialogue
  lane -2           music bed, role music, ducking keyframes under every narration line
chapter markers     one per section title
```

Every time in the file is absolute, which keeps retimed clips from shifting what is anchored
to them. To edit on the primary storyline, select the lane-1 storyline and choose
Edit → Overwrite to Primary Storyline.

| Timeline | FCPXML |
|---|---|
| captured section | `asset-clip`, in-point and duration from the reconcile |
| `playbackRate` ≠ 1, or a held last frame | a `timeMap` on the clip; a flat last segment is the hold |
| crossfade | the selected downloaded Motion transition, otherwise Cross Dissolve; overlap split into handles |
| `titlecard` | a `title` on the storyline: title, then subtitle |
| `onScreenText` | a lower-third `title` on lane 2 |
| captions | `caption` elements |
| music `duckRanges` | `adjust-volume` keyframes; lines closer than two ramps merge into one duck |
| `camera` centred | `adjust-transform` scale keyframes |
| `sections[].fcp.effectTemplate` | a downloaded Motion effect as `filter-video` |
| section start | `chapter-marker`, which Share turns into chapters |

## What does not carry over

The export prints a `note` for each:

- `fadeThroughBlack` and `slide` become Cross Dissolves.
- A camera move toward a point other than the centre becomes a marker saying where; set it
  in FCP.
- `code` sections become a gap with a marker. Render that range from Remotion
  (`npx remotion render Demo out/<id>.mov --codec prores --frames=<start>-<end>` in
  `demo/studio`) and drop it in.
- Remotion's `theme.ts` styling does not exist in FCP; that is the point of this finish.

## Importing and finishing

1. File → Import → XML, or `open -a "<Final Cut Pro app name>" demo/out/demo.fcpxml`, and
   choose a library.
2. Media is referenced in place by absolute path. Do not move `demo/` after exporting, or
   relink in FCP.
3. Choose titles, adjust lower thirds, fine-tune.
4. Share → Export File (or a YouTube preset) to `demo/out/demo-fcp.mov` or `.mp4`. Verify the
   export dialog's Source and exact destination; wait for the expected duration and decoded frame
   count, not merely file existence. If captions are required, select Roles → Closed Captions →
   Burn in captions, re-read the selection, and verify the replacement movie's actual pixels.
5. Review it like any render: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/extract-frames.sh demo/out/demo-fcp.mp4`.
   Check active-caption timestamps, dense logo holds, and entrance/hold/exit samples. Run
   `scripts/fcp-finish-manifest.mjs` before handoff and leave the status at
`pending-human-watch-listen` until a person approves taste, pacing, pronunciation, and mix.

## Approved delivery and recovery

Use `meta.videoId` (for example `01-rex-overview`) and `meta.version` (`v1`, `v2`) to namespace
every approved cut. Do not overwrite an approved version or clean another video's work directory.
After approval, consolidate used media into a fresh Final Cut library with external media copied
in, close the library before packaging, and retain only the native library, byte-checked movie,
source storyboard/timeline snapshots, captions, music master, prerequisites, and manifests.
Restore to a fresh path with the original sources unavailable and inspect the restored project and
export. A valid ZIP or XML parse is not proof that native logo bindings survived. Cleanup is a
separate, explicitly scoped post-approval step; Git commit/push still requires authorization.

## Rules

- **Hand edits come after picture lock.** A re-export makes a new project. It never updates
  the one you edited, so every edit made before a re-capture is lost.
- **FCP has no headless render.** Native UI automation may assist when permissions and current
  accessibility observations are available, but the last step is still state-checked Share plus
  human watch/listen approval. Say so in the report instead of implying the video is done.
- **First import on a new FCP version**: check that the held frames hold, the cross dissolves
  have handles, lower thirds carry their text, and captions sit in the caption lane. The DTD
  proves the file is well-formed FCPXML; only FCP proves it means what the timeline means.
