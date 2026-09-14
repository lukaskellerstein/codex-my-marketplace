#!/usr/bin/env node
// Prepare local YouTube metadata beside an approved video. This never uploads,
// publishes, or overwrites a manually edited package.

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const args = process.argv.slice(2);
const value = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const project = resolve(value('--project', '.'));
const storyboardPath = join(project, 'demo', 'storyboard.json');
const timelinePath = join(project, 'demo', 'timeline.json');
const storyboard = JSON.parse(readFileSync(storyboardPath, 'utf8'));
const timeline = JSON.parse(readFileSync(timelinePath, 'utf8'));
const videoId = storyboard.meta?.videoId;
if (!videoId) throw new Error('demo-video: meta.videoId is required before preparing a YouTube package.');
if (!/^\d{2}-[a-z0-9][a-z0-9-]*$/.test(videoId)) throw new Error(`demo-video: invalid meta.videoId "${videoId}"`);

const root = join(project, 'demo', videoId);
const finalDir = join(root, 'final');
const youtubeDir = join(root, 'youtube');
const movie = value('--movie', join(finalDir, 'demo-fcp.mp4'));
const description = storyboard.meta?.youtube?.description ?? [
  storyboard.meta.title,
  '',
  `Audience: ${storyboard.meta.audience}`,
  '',
  ...(storyboard.meta.youtube?.capabilities ?? (storyboard.sections ?? []).map((s) => `- ${s.title}`)),
  '',
  ...(storyboard.meta.youtube?.urls ?? []).map((url) => String(url)),
].join('\n');
const title = String(storyboard.meta?.youtube?.title ?? storyboard.meta.title ?? videoId);
const chapters = (timeline.sections ?? []).map((section) => ({
  startSeconds: Number(section.startSeconds ?? section.startFrame / (timeline.fps || 30)),
  title: section.title
})).filter((chapter) => chapter.title);

mkdirSync(youtubeDir, { recursive: true });
const metadataPath = join(youtubeDir, 'upload-package.json');
const readExisting = (path) => { try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; } };
const existing = readExisting(metadataPath);
const sha256 = existsSync(movie) ? createHash('sha256').update(readFileSync(movie)).digest('hex') : null;
const packageData = existing && existing.movieSha256 === sha256 ? existing : {
  generatedAt: new Date().toISOString(), videoId, movie, movieSha256: sha256,
  title, description, chapters, thumbnail: null,
  checks: { sourceLinksCheckedAt: null, imageCheckedAt: null, currentYouTubeRequirementsCheckedAt: null },
  disclosure: { narration: storyboard.meta?.voice?.provider ? 'review-required' : 'unknown', music: storyboard.meta?.music ? 'review-required' : 'unknown' },
  upload: { authorized: false, status: 'local-review-only' }
};
writeFileSync(metadataPath, `${JSON.stringify(packageData, null, 2)}\n`);

const readmePath = join(youtubeDir, 'README.md');
if (!existsSync(readmePath)) {
  writeFileSync(readmePath, `# YouTube package — ${videoId}\n\n` +
    `Prepared locally from the approved movie: \`${movie}\`.\n\n` +
    `Review and complete \`upload-package.json\` before upload. This package does not upload, publish, schedule, commit, or push anything.\n\n` +
    `## Title\n\n${packageData.title}\n\n## Description\n\n${packageData.description}\n\n## Chapters\n\n` +
    packageData.chapters.map((c) => `- ${c.startSeconds.toFixed(3)}s — ${c.title}`).join('\n') + '\n');
}
console.log(`demo-video: YouTube package -> ${youtubeDir}`);
console.log(`  metadata: ${metadataPath}`);
console.log(`  movie checksum: ${sha256 ?? 'missing — provide the approved final movie'}`);
console.log(`  manual README preserved: ${existsSync(readmePath)}`);
