export function canonicalTitle(s){return String(s).trim().replace(/\s+\(\d+\)$/,'').replace(/\s+/g,' ')}
export function naturalKey(s){return String(s).split(/(\d+)/).map(x=>/^\d+$/.test(x)?Number(x):x.toLocaleLowerCase('pt-BR'))}
export function naturalCompare(a,b){const A=naturalKey(a),B=naturalKey(b);for(let i=0;i<Math.max(A.length,B.length);i++){if(A[i]===undefined)return -1;if(B[i]===undefined)return 1;if(A[i]===B[i])continue;if(typeof A[i]==='number'&&typeof B[i]==='number')return A[i]-B[i];return String(A[i]).localeCompare(String(B[i]),'pt-BR')}return 0}

export function validateManifest(input){
  if(!input||typeof input!=='object'||Array.isArray(input))throw new Error('catalog must be an object');
  if(!Number.isInteger(input.revision)||input.revision<0)throw new Error('invalid revision');
  if(!Array.isArray(input.works))throw new Error('works must be an array');
  const workIds=new Set(),editionIds=new Set(),tombstones=new Set();
  for(const raw of input.works){
    if(!raw||typeof raw!=='object'||Array.isArray(raw))throw new Error('invalid work');
    const id=typeof raw.id==='string'?raw.id.trim():''; if(!id)throw new Error('work id missing');
    if(workIds.has(id))throw new Error(`duplicate work id: ${id}`); workIds.add(id);
    if(!['book','hq','manga','graphic_novel'].includes(raw.type))throw new Error(`invalid work type for ${id}: ${raw.type}`);
    const title=typeof raw.displayTitle==='string'&&raw.displayTitle.trim()?raw.displayTitle:(typeof raw.canonicalTitle==='string'?raw.canonicalTitle:'');
    if(!title.trim())throw new Error(`work title missing for ${id}`);
    if(!Array.isArray(raw.editions))throw new Error(`editions must be an array for ${id}`);
    for(const key of ['sections','editorialSections','tags']){
      const v=raw[key]; if(v!==undefined&&(!Array.isArray(v)||v.some(x=>typeof x!=='string'||!x.trim())))throw new Error(`${key} must be a non-empty string array for ${id}`);
    }
    for(const e of raw.editions){
      if(!e||typeof e!=='object'||Array.isArray(e))throw new Error(`invalid edition in ${id}`);
      const eid=typeof e.id==='string'?e.id.trim():''; if(!eid)throw new Error(`edition id missing in ${id}`);
      if(editionIds.has(eid))throw new Error(`duplicate edition id: ${eid}`); editionIds.add(eid);
      if(!['pdf','epub','cbz','cbr'].includes(e.format))throw new Error(`invalid edition format for ${eid}: ${e.format}`);
      if(typeof e.sourceFileId!=='string'||!e.sourceFileId.trim())throw new Error(`sourceFileId missing for ${eid}`);
      if(typeof e.fileName!=='string'||!e.fileName.trim())throw new Error(`fileName missing for ${eid}`);
      if(e.byteSize!=null&&(!Number.isInteger(e.byteSize)||e.byteSize<0))throw new Error(`invalid byteSize for ${eid}`);
    }
  }
  for(const raw of input.tombstones??[]){
    const kind=raw?.kind??raw?.entityType, id=raw?.id??raw?.entityId;
    if(!['work','edition'].includes(kind)||typeof id!=='string'||!id)throw new Error('invalid tombstone');
    const key=`${kind}:${id}`; if(tombstones.has(key))throw new Error(`duplicate tombstone: ${key}`); tombstones.add(key);
    if(kind==='work'&&workIds.has(id))throw new Error(`work both present and tombstoned: ${id}`);
    if(kind==='edition'&&editionIds.has(id))throw new Error(`edition both present and tombstoned: ${id}`);
  }
  return true;
}
