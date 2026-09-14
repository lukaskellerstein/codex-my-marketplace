#!/usr/bin/env node
// Write a small, auditable manifest for a Final Cut Pro handoff.
// It records exact inputs and native template availability without claiming
// that FCPXML preserves controls which require a hand edit in Final Cut Pro.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { listMotionTemplates } from './lib/fcp.mjs';

const args = process.argv.slice(2);
const value = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const project = resolve(value('--project', '.'));
const out = resolve(value('--out', join(project, 'demo', 'out', 'fcp-finish-manifest.json')));
const storyboardPath = join(project, 'demo', 'storyboard.json');
const timelinePath = join(project, 'demo', 'timeline.json');
const outputCandidates = ['demo/out/demo-fcp.mov', 'demo/out/demo-fcp.mp4', 'demo/out/demo.mp4'];

const sha256 = (path) => {
  if (!existsSync(path)) return null;
  return createHash('sha256').update(readFileSync(path)).digest('hex');
};
const readJson = (path) => {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; }
};

const storyboard = readJson(storyboardPath) ?? {};
const templates = listMotionTemplates({ includePlaceholders: true });
const selected = new Set();
const fcp = storyboard.meta?.fcp ?? {};
for (const key of ['titleTemplate', 'lowerThirdTemplate', 'transitionTemplate']) {
  if (fcp[key]) selected.add(String(fcp[key]).toUpperCase());
}
for (const section of storyboard.sections ?? []) {
  for (const value of [section.transitionIn?.fcpTemplate, section.fcp?.effectTemplate]) {
    if (value) selected.add(String(value).toUpperCase());
  }
}

const templateRows = [...selected].map((selector) => {
  const matches = templates.filter((t) => t.motionVfxToken === selector || t.uid === selector || `${t.category}/${t.name}` === selector);
  return {
    selector,
    matches: matches.map(({ name, category, kind, uid, availability, motionVfxToken }) =>
      ({ name, category, kind, uid, availability, motionVfxToken }))
  };
});

const unresolvedManualControls = [
  'Assign and verify every template media well with the real logo/source media.',
  'Clear unused text fields and verify field order using sentinel text in a disposable title probe.',
  'Check font, contrast, safe placement, entrance, settled hold, and exit over representative light and dark footage.',
  'Export from Final Cut Pro and review decoded pixels; FCPXML validity alone is insufficient.',
  'Verify caption burn-in selection and final movie duration/frame count before delivery.'
];

const manifest = {
  generatedAt: new Date().toISOString(),
  project,
  authoritativeRenderer: storyboard.meta?.authoritativeRenderer ?? (storyboard.meta?.fcp ? 'final-cut-pro' : 'remotion'),
  videoId: storyboard.meta?.videoId ?? null,
  version: storyboard.meta?.version ?? null,
  inputs: {
    storyboard: { path: storyboardPath, sha256: sha256(storyboardPath) },
    timeline: { path: timelinePath, sha256: sha256(timelinePath) },
    narration: (storyboard.sections ?? []).map((section) => {
      const path = join(project, 'demo', 'audio', `${section.id}.mp3`);
      return { id: section.id, path, sha256: sha256(path) };
    }).filter((row) => row.sha256)
  },
  outputs: outputCandidates.map((relative) => {
    const path = join(project, relative);
    return { path, sha256: sha256(path) };
  }).filter((row) => row.sha256),
  voice: storyboard.meta?.voice ?? null,
  selectedMotionVfx: templateRows,
  unresolvedManualControls,
  review: { status: 'pending-human-watch-listen', exportedMovie: null, nativeLibrary: null }
};

writeFileSync(out, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`demo-video: FCP finish manifest -> ${out}`);
console.log(`  selected MotionVFX selectors: ${templateRows.length}`);
console.log('  review status: pending-human-watch-listen');
