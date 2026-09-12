'use strict';
const fs=require('fs');
const path=require('path');
const optional=process.argv.includes('--optional');
const seedPath=path.resolve(process.env.LUME_SEED_FILE||'/seed/lume-seed.json');
const requireSeed=String(process.env.LUME_REQUIRE_SEED||'').toLowerCase()==='1'||String(process.env.LUME_REQUIRE_SEED||'').toLowerCase()==='true';
if(!fs.existsSync(seedPath)){
  if(requireSeed||!optional)throw new Error(`required seed missing: ${seedPath}`);
  console.log(`seed skipped: ${seedPath} not present`);
  process.exit(0);
}
const {store,validateCatalogManifest,validateMediaEntry}=require('./server.runtime.js');
try{
  const input=JSON.parse(fs.readFileSync(seedPath,'utf8'));
  const catalog=input.catalog;
  const media=Array.isArray(input.media)?input.media:[];
  validateCatalogManifest(catalog);
  const known=new Set(catalog.works.flatMap(w=>(w.editions||[]).map(e=>e.id)));
  const entries=media.map(x=>validateMediaEntry(x,process.env));
  for(const e of entries)if(!known.has(e.editionId))throw new Error(`seed media references unknown edition: ${e.editionId}`);
  store.installCatalog(catalog);
  for(const e of entries){const {editionId,...meta}=e;store.registerMedia(editionId,meta)}
  if(process.env.LUME_SEED_PRUNE_MEDIA==='1'){
    const keep=new Set(entries.map(x=>x.editionId));
    for(const existing of store.listMedia())if(!keep.has(existing.editionId))store.removeMedia(existing.editionId);
  }
  console.log(`seed installed: revision=${catalog.revision} works=${catalog.works.length} media=${entries.length}`);
}finally{if(typeof store.close==='function')store.close()}
