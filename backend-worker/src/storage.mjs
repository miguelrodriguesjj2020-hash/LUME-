function rows(r){return r?.results||[]}
function isoNow(){return new Date().toISOString()}
function parseArray(v){try{const x=JSON.parse(v||'[]');return Array.isArray(x)?x:[]}catch{return []}}

export class D1Store {
  constructor(db){this.db=db}
  async getRevision(){const r=await this.db.prepare("SELECT value FROM catalog_meta WHERE key='revision'").first();const n=Number(r?.value??0);return Number.isInteger(n)&&n>=0?n:0}
  async readiness(){await this.db.prepare('SELECT 1 AS ok').first();return {ok:true,durable:true,revision:await this.getRevision()}}
  async bootstrap(since=null){
    const revision=await this.getRevision(); const s=Number(since);
    if(Number.isInteger(s)&&s===revision)return {notModified:true,revision};
    const works=rows(await this.db.prepare(`SELECT id,canonical_title,display_title,type,published,updated_at,sections_json,editorial_sections_json,tags_json FROM works WHERE published=1 ORDER BY canonical_title`).all());
    const sources=rows(await this.db.prepare('SELECT work_id,source_folder_id FROM work_sources ORDER BY work_id,source_folder_id').all());
    const editions=rows(await this.db.prepare(`SELECT id,work_id,language,format,volume_number,chapter_number,source_file_id,file_name,byte_size,sha256,reading_direction,source_revision,updated_at FROM editions ORDER BY work_id,COALESCE(volume_number,999999),COALESCE(chapter_number,999999),file_name`).all());
    const sourceMap=new Map();for(const srow of sources){if(!sourceMap.has(srow.work_id))sourceMap.set(srow.work_id,[]);sourceMap.get(srow.work_id).push(srow.source_folder_id)}
    const editionMap=new Map();for(const e of editions){if(!editionMap.has(e.work_id))editionMap.set(e.work_id,[]);editionMap.get(e.work_id).push({id:e.id,language:e.language,format:e.format,volumeNumber:e.volume_number,chapterNumber:e.chapter_number,sourceFileId:e.source_file_id,fileName:e.file_name,byteSize:e.byte_size,sha256:e.sha256,readingDirection:e.reading_direction,sourceRevision:e.source_revision,updatedAt:e.updated_at})}
    return {revision,full:true,works:works.map(w=>({id:w.id,canonicalTitle:w.canonical_title,displayTitle:w.display_title,type:w.type,published:!!w.published,updatedAt:w.updated_at,sourceFolderIds:sourceMap.get(w.id)||[],sections:parseArray(w.sections_json),editorialSections:parseArray(w.editorial_sections_json),tags:parseArray(w.tags_json),editions:editionMap.get(w.id)||[]})),tombstones:[]};
  }
  async getEdition(id){return this.db.prepare('SELECT id,source_file_id,file_name,byte_size,sha256,source_revision FROM editions WHERE id=?').bind(id).first()}
  async getAccount(username){return this.db.prepare(`SELECT id,username,password_verifier,role,profile_id,disabled FROM accounts WHERE username=? COLLATE NOCASE`).bind(username).first()}
  async getIdempotent(opId){const r=await this.db.prepare('SELECT response_json FROM idempotency WHERE op_id=?').bind(opId).first();return r?JSON.parse(r.response_json):null}
  async putIdempotent(opId,response){await this.db.prepare('INSERT OR REPLACE INTO idempotency(op_id,response_json,created_at) VALUES(?,?,?)').bind(opId,JSON.stringify(response),isoNow()).run()}
  async getProgress(profileId,editionId){const r=await this.db.prepare(`SELECT profile_id,edition_id,locator_json,percent,completed,client_updated_at,server_updated_at,op_id FROM progress WHERE profile_id=? AND edition_id=?`).bind(profileId,editionId).first();return r?{profileId:r.profile_id,editionId:r.edition_id,locator:JSON.parse(r.locator_json),percent:r.percent,completed:!!r.completed,clientUpdatedAt:Number(r.client_updated_at),serverUpdatedAt:r.server_updated_at,opId:r.op_id}:null}
  async saveProgress(p){
    await this.db.prepare(`INSERT INTO progress(profile_id,edition_id,locator_json,percent,completed,client_updated_at,server_updated_at,op_id) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(profile_id,edition_id) DO UPDATE SET locator_json=excluded.locator_json,percent=excluded.percent,completed=excluded.completed,client_updated_at=excluded.client_updated_at,server_updated_at=excluded.server_updated_at,op_id=excluded.op_id`).bind(p.profileId,p.editionId,JSON.stringify(p.locator),p.percent,p.completed?1:0,p.clientUpdatedAt,p.serverUpdatedAt,p.opId).run();
    const ev=await this.db.prepare(`INSERT INTO sync_events(profile_id,entity_type,entity_id,payload_json,server_updated_at) VALUES(?,?,?,?,?) RETURNING seq`).bind(p.profileId,'progress',p.editionId,JSON.stringify(p),p.serverUpdatedAt).first(); return ev?.seq||null;
  }
  async sync(profileId,cursor=0,limit=500){
    const c=Number(cursor); if(!Number.isInteger(c)||c<0)throw new Error('invalid cursor');
    const rs=rows(await this.db.prepare(`SELECT seq,entity_type,entity_id,payload_json,server_updated_at FROM sync_events WHERE profile_id=? AND seq>? ORDER BY seq LIMIT ?`).bind(profileId,c,limit).all());
    let next=c;const events=[];for(const e of rs){next=Math.max(next,Number(e.seq));if(e.entity_type==='progress')events.push({seq:Number(e.seq),profile:profileId,edition:e.entity_id,payload:JSON.parse(e.payload_json)});}
    return {cursor:String(next),events,hasMore:rs.length===limit};
  }
}
