#!/usr/bin/env node
// Materialize public motionVFX preview stills and videos for a small, already-downloaded
// shortlist so Codex can inspect the real designs before choosing FCP templates.
//
// usage:
//   motionvfx-previews.mjs --tokens 51PI,6RRA,6FF7 --out /tmp/mvfx-shortlist
//   motionvfx-previews.mjs --tokens 51PI,6RRA --out /tmp/mvfx-shortlist --images-only

import { mkdirSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { basename, join, resolve } from 'node:path';
import { listMotionTemplates } from './lib/fcp.mjs';
import { fetchMotionVfxPreviews } from './lib/motionvfx.mjs';

const args = process.argv.slice(2);
const argOf = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

if (args.includes('--help') || args.includes('-h')) {
  console.log('usage: motionvfx-previews.mjs --tokens TOKEN[,TOKEN…] --out DIR [--images-only]');
  process.exit(0);
}

const tokens = [...new Set(String(argOf('--tokens') ?? '').split(',').map((value) => value.trim().toUpperCase()).filter(Boolean))];
const outArg = argOf('--out');
if (!tokens.length || !outArg) {
  console.error('demo-video: --tokens and --out are required.');
  process.exit(1);
}
if (tokens.length > 12) {
  console.error('demo-video: inspect at most 12 motionVFX candidates per pass; make a tighter editorial shortlist.');
  process.exit(1);
}
if (tokens.some((token) => !/^[A-Z0-9]{4}$/.test(token))) {
  console.error('demo-video: every motionVFX token must be four uppercase letters/digits.');
  process.exit(1);
}

const installed = listMotionTemplates({ availability: 'downloaded' }).filter(
  (template) => template.provider === 'motionvfx' && template.motionVfxToken
);
const byToken = new Map(installed.map((template) => [template.motionVfxToken, template]));
const missing = tokens.filter((token) => !byToken.has(token));
if (missing.length) {
  console.error(
    `demo-video: ${missing.join(', ')} ${missing.length === 1 ? 'is' : 'are'} not a downloaded motionVFX template. ` +
      'Catalog placeholders must be downloaded in mExtension before use.'
  );
  process.exit(1);
}

const outDir = resolve(outArg);
mkdirSync(outDir, { recursive: true });
const previews = await fetchMotionVfxPreviews(tokens, { maxWidth: 960 });
const manifest = [];

async function download(url, destination) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`preview download returned ${response.status}`);
  writeFileSync(destination, Buffer.from(await response.arrayBuffer()));
}

for (const preview of previews) {
  const template = byToken.get(preview.token);
  const row = { ...preview, template, files: {} };
  if (preview.error) {
    manifest.push(row);
    continue;
  }
  try {
    if (preview.image?.url) {
      const extension = preview.image.format === 'jpeg' ? 'jpg' : preview.image.format;
      const destination = join(outDir, `${preview.token}-still.${extension}`);
      await download(preview.image.url, destination);
      row.files.image = destination;
    }
    if (!args.includes('--images-only') && preview.video?.url) {
      const extension = basename(new URL(preview.video.url).pathname).split('.').pop() || 'mp4';
      const destination = join(outDir, `${preview.token}-preview.${extension}`);
      await download(preview.video.url, destination);
      row.files.video = destination;
      try {
        row.videoDurationSeconds = Number(
          execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', destination], {
            encoding: 'utf8',
          }).trim()
        );
      } catch {
        row.videoDurationSeconds = null;
      }
    }
  } catch (error) {
    row.downloadError = error.message;
  }
  manifest.push(row);
}

const manifestPath = join(outDir, 'manifest.json');
writeFileSync(manifestPath, `${JSON.stringify({ generatedAt: new Date().toISOString(), previews: manifest }, null, 2)}\n`);
console.log(`demo-video: ${manifest.length} motionVFX preview set(s) -> ${outDir}`);
console.log(`  manifest: ${manifestPath}`);
for (const row of manifest) {
  const status = row.error ?? row.downloadError ?? Object.values(row.files).join(', ');
  console.log(`  ${row.token} ${row.name ?? row.template.name}: ${status}`);
}
