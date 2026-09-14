export function validateCatalogManifest(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('catalog must be an object');
  if (!Number.isInteger(input.revision) || input.revision < 0) throw new Error('invalid revision');
  if (!Array.isArray(input.works)) throw new Error('works must be an array');
  const workIds = new Set(), editionIds = new Set(), tombstoneKeys = new Set();
  for (const w of input.works) {
    if (!w || typeof w !== 'object' || Array.isArray(w)) throw new Error('invalid work');
    const wid = typeof w.id === 'string' ? w.id.trim() : '';
    if (!wid) throw new Error('work id missing');
    if (workIds.has(wid)) throw new Error(`duplicate work id: ${wid}`);
    workIds.add(wid);
    if (!['book', 'hq', 'manga', 'graphic_novel', 'magazine'].includes(w.type)) throw new Error(`invalid work type for ${wid}: ${w.type}`);
    const title = typeof w.displayTitle === 'string' && w.displayTitle.trim() ? w.displayTitle : (typeof w.canonicalTitle === 'string' ? w.canonicalTitle : '');
    if (!title.trim()) throw new Error(`work title missing for ${wid}`);
    const cover = w.cover;
    if (!cover || typeof cover !== 'object' || Array.isArray(cover)) throw new Error(`cover missing for ${wid}`);
    if (typeof cover.sourceFileId !== 'string' || !cover.sourceFileId.trim()) throw new Error(`cover sourceFileId missing for ${wid}`);
    if (typeof cover.fileName !== 'string' || !cover.fileName.trim()) throw new Error(`cover fileName missing for ${wid}`);
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(cover.mimeType)) throw new Error(`invalid cover mimeType for ${wid}: ${cover.mimeType}`);
    if (!Number.isInteger(cover.byteSize) || cover.byteSize < 1) throw new Error(`invalid cover byteSize for ${wid}`);
    if (typeof cover.sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(cover.sha256)) throw new Error(`invalid cover sha256 for ${wid}`);
    if (!Array.isArray(w.editions)) throw new Error(`editions must be an array for ${wid}`);
    for (const key of ['sections', 'editorialSections', 'tags']) {
      const value = w[key];
      if (value !== undefined && (!Array.isArray(value) || value.some(x => typeof x !== 'string' || !x.trim()))) {
        throw new Error(`${key} must be a non-empty string array for ${wid}`);
      }
    }
    for (const e of w.editions) {
      if (!e || typeof e !== 'object' || Array.isArray(e)) throw new Error(`invalid edition in ${wid}`);
      const eid = typeof e.id === 'string' ? e.id.trim() : '';
      if (!eid) throw new Error(`edition id missing in ${wid}`);
      if (editionIds.has(eid)) throw new Error(`duplicate edition id: ${eid}`);
      editionIds.add(eid);
      if (!['pdf', 'epub', 'cbz'].includes(e.format)) throw new Error(`invalid edition format for ${eid}: ${e.format}`);
      if (typeof e.sourceFileId !== 'string' || !e.sourceFileId.trim()) throw new Error(`sourceFileId missing for ${eid}`);
      if (typeof e.fileName !== 'string' || !e.fileName.trim()) throw new Error(`fileName missing for ${eid}`);
    }
  }
  const tombstones = input.tombstones ?? [];
  if (!Array.isArray(tombstones)) throw new Error('tombstones must be an array');
  for (const t of tombstones) {
    if (!t || typeof t !== 'object' || Array.isArray(t)) throw new Error('invalid tombstone');
    const id = typeof t.id === 'string' ? t.id.trim() : '';
    if (!id || !['work', 'edition'].includes(t.kind)) throw new Error('invalid tombstone');
    const key = `${t.kind}:${id}`;
    if (tombstoneKeys.has(key)) throw new Error(`duplicate tombstone: ${key}`);
    tombstoneKeys.add(key);
    if (t.kind === 'work' && workIds.has(id)) throw new Error(`work both present and tombstoned: ${id}`);
    if (t.kind === 'edition' && editionIds.has(id)) throw new Error(`edition both present and tombstoned: ${id}`);
  }
  return true;
}

export function validateProgress(editionId, p) {
  if (typeof p?.opId !== 'string' || !p.opId.trim()) throw new Error('opId required');
  if (typeof editionId !== 'string' || !editionId.trim()) throw new Error('editionId required');
  if (!Number.isInteger(p.clientUpdatedAt) || p.clientUpdatedAt < 0) throw new Error('invalid clientUpdatedAt');
  if (typeof p.completed !== 'boolean') throw new Error('completed must be boolean');
  if (typeof p.percent !== 'number' || !Number.isFinite(p.percent) || p.percent < 0 || p.percent > 1) throw new Error('invalid percent');
  if (!p.locator || typeof p.locator !== 'object' || Array.isArray(p.locator)) throw new Error('invalid locator');
}

export function shouldAcceptProgress(old, incoming) {
  return !old ||
    (!old.completed && incoming.completed) ||
    (!old.completed && !incoming.completed && incoming.clientUpdatedAt >= old.clientUpdatedAt) ||
    (old.completed && incoming.completed && incoming.clientUpdatedAt >= old.clientUpdatedAt);
}
