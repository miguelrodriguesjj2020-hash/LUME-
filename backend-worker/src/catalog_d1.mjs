import {validateManifest} from './catalog.mjs';
function n(v){return v==null?null:Number(v)}
function js(v){return JSON.stringify(Array.isArray(v)?v:[])}
export async function applyCatalogManifest(db,manifest){
  validateManifest(manifest);
  const currentRow=await db.prepare("SELECT value FROM catalog_meta WHERE key='revision'").first();
  const current=Number(currentRow?.value??0); if(Number.isFinite(current)&&manifest.revision<current)throw new Error('catalog_revision_regression');
  const stmts=[];
  if(manifest.full===true){
    stmts.push(db.prepare('DELETE FROM editions'));
    stmts.push(db.prepare('DELETE FROM work_sources'));
    stmts.push(db.prepare('DELETE FROM works'));
  }
  for(const w of manifest.works){
    const updated=w.updatedAt||manifest.generatedAt||new Date().toISOString();
    stmts.push(db.prepare(`INSERT INTO works(id,canonical_title,display_title,type,published,updated_at,sections_json,editorial_sections_json,tags_json) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET canonical_title=excluded.canonical_title,display_title=excluded.display_title,type=excluded.type,published=excluded.published,updated_at=excluded.updated_at,sections_json=excluded.sections_json,editorial_sections_json=excluded.editorial_sections_json,tags_json=excluded.tags_json`).bind(w.id,w.canonicalTitle||w.displayTitle,w.displayTitle||w.canonicalTitle,w.type,w.published===false?0:1,updated,js(w.sections),js(w.editorialSections),js(w.tags)));
    stmts.push(db.prepare('DELETE FROM work_sources WHERE work_id=?').bind(w.id));
    for(const source of w.sourceFolderIds||[])stmts.push(db.prepare('INSERT INTO work_sources(work_id,source_folder_id) VALUES(?,?)').bind(w.id,source));
    if(manifest.full!==true){
      const existing=await db.prepare('SELECT id FROM editions WHERE work_id=?').bind(w.id).all();
      const keep=new Set((w.editions||[]).map(e=>e.id));
      for(const row of existing?.results||[])if(!keep.has(row.id))stmts.push(db.prepare('DELETE FROM editions WHERE id=?').bind(row.id));
    }
    for(const e of w.editions||[]){
      const eu=e.updatedAt||updated;
      stmts.push(db.prepare(`INSERT INTO editions(id,work_id,language,format,volume_number,chapter_number,source_file_id,file_name,byte_size,sha256,reading_direction,source_revision,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,language=excluded.language,format=excluded.format,volume_number=excluded.volume_number,chapter_number=excluded.chapter_number,source_file_id=excluded.source_file_id,file_name=excluded.file_name,byte_size=excluded.byte_size,sha256=excluded.sha256,reading_direction=excluded.reading_direction,source_revision=excluded.source_revision,updated_at=excluded.updated_at`).bind(e.id,w.id,e.language||'unknown',e.format,n(e.volumeNumber),n(e.chapterNumber),e.sourceFileId,e.fileName,e.byteSize==null?null:Number(e.byteSize),e.sha256||null,e.readingDirection||'auto',String(manifest.revision),eu));
    }
  }
  for(const t of manifest.tombstones||[]){
    const kind=t.kind??t.entityType,id=t.id??t.entityId;
    if(kind==='edition')stmts.push(db.prepare('DELETE FROM editions WHERE id=?').bind(id));
    if(kind==='work'){
      stmts.push(db.prepare('DELETE FROM editions WHERE work_id=?').bind(id));
      stmts.push(db.prepare('DELETE FROM work_sources WHERE work_id=?').bind(id));
      stmts.push(db.prepare('DELETE FROM works WHERE id=?').bind(id));
    }
  }
  stmts.push(db.prepare("INSERT INTO catalog_meta(key,value) VALUES('revision',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").bind(String(manifest.revision)));
  return db.batch(stmts);
}
