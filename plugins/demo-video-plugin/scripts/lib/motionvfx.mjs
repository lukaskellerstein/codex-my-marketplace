// Public motionVFX DesignStudio metadata used to map local template tokens to preview media
// and current collection membership. Local inventory remains fully offline; these helpers are
// called only by explicit --previews or --collections commands.

export const MOTIONVFX_API_BASE = 'https://www.motionvfx.com/design-studio/api/v2';

const assertToken = (token) => {
  const value = String(token ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9]{4}$/.test(value)) throw new Error(`invalid motionVFX token "${token}"`);
  return value;
};

async function apiJson(path, { fetchImpl = globalThis.fetch } = {}) {
  if (typeof fetchImpl !== 'function') throw new Error('motionVFX preview lookup needs Node 18+ (global fetch)');
  const response = await fetchImpl(`${MOTIONVFX_API_BASE}${path}`, {
    headers: { accept: 'application/json' },
  });
  if (!response.ok) throw new Error(`motionVFX API ${response.status} for ${path}`);
  const json = await response.json();
  if (!json?.data) throw new Error(`motionVFX API returned no data for ${path}`);
  return json.data;
}

function rendition(group, formats, maxWidth = 960) {
  const sizes = Object.entries(group ?? {})
    .map(([width, variants]) => ({ width: Number(width), variants }))
    .filter((item) => Number.isFinite(item.width))
    .sort((a, b) => b.width - a.width);
  const picked = sizes.find((item) => item.width <= maxWidth) ?? sizes.at(-1);
  if (!picked) return null;
  for (const format of formats) {
    const value = picked.variants?.[format];
    if (value?.src) return { url: value.src, width: value.width, height: value.height, format };
  }
  return null;
}

export async function fetchMotionVfxPreview(token, options = {}) {
  const normalized = assertToken(token);
  const data = await apiJson(`/elements/${encodeURIComponent(normalized)}`, options);
  const element = Array.isArray(data.results) ? data.results[0] : data.results;
  if (!element?.token) throw new Error(`motionVFX has no element for token ${normalized}`);

  const durationFrames = Number(element.extra_data?.duration);
  const frameRate = Number(element.extra_data?.frameRate);
  const templateDurationSeconds =
    Number.isFinite(durationFrames) && Number.isFinite(frameRate) && frameRate > 0
      ? Number((durationFrames / frameRate).toFixed(3))
      : null;
  const detailPath = String(element.detail_url ?? `/elements/${normalized}`);

  return {
    token: normalized,
    name: element.name,
    releaseDate: element.release_date ?? null,
    detailUrl: `https://www.motionvfx.com/design-studio${detailPath.startsWith('/') ? '' : '/'}${detailPath}`,
    templateDurationSeconds,
    image: rendition(element.grid_prev_img_data, ['webp', 'jpeg'], options.maxWidth),
    video: rendition(element.grid_prev_video_data, ['h264', 'h265'], options.maxWidth),
    styles: (element.styles ?? element.style_list ?? []).map((style) => style.name ?? style).filter(Boolean),
    tags: (element.tags ?? element.tag_list ?? []).map((tag) => tag.name ?? tag).filter(Boolean),
  };
}

async function mapLimit(items, concurrency, worker) {
  const output = new Array(items.length);
  let cursor = 0;
  async function run() {
    while (cursor < items.length) {
      const index = cursor++;
      output[index] = await worker(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, run));
  return output;
}

export async function fetchMotionVfxPreviews(tokens, { concurrency = 6, ...options } = {}) {
  return mapLimit([...new Set(tokens.map(assertToken))], concurrency, async (token) => {
    try {
      return await fetchMotionVfxPreview(token, options);
    } catch (error) {
      return { token, error: error.message };
    }
  });
}

export async function fetchMotionVfxCollections(downloadedTokens, { concurrency = 6, ...options } = {}) {
  const installed = new Set(downloadedTokens.map(assertToken));
  const collections = [];
  for (let page = 1; ; page += 1) {
    const query = new URLSearchParams({ include: 'id,name,slug,type', per_page: '100', page: String(page) });
    const data = await apiJson(`/collections?${query}`, options);
    collections.push(...(data.results ?? []));
    if (!data.has_next) break;
  }

  const resolved = await mapLimit(collections, concurrency, async (collection) => {
    const data = await apiJson(`/collections/${encodeURIComponent(collection.slug)}/elements`, options);
    const elements = data.results ?? [];
    const downloaded = elements.filter((element) => installed.has(element.token));
    return {
      id: collection.id,
      name: collection.name,
      slug: collection.slug,
      type: collection.type,
      downloadedCount: downloaded.length,
      totalCount: elements.length,
      coverage: elements.length ? Number((downloaded.length / elements.length).toFixed(4)) : 0,
      downloadedTokens: downloaded.map((element) => element.token),
      missing: elements
        .filter((element) => !installed.has(element.token))
        .map((element) => ({ token: element.token, name: element.name, kind: element.fcp_kind ?? null })),
    };
  });
  return resolved.filter((collection) => collection.downloadedCount > 0);
}
