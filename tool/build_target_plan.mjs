#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2);
const value=(name,fallback)=>{const i=args.indexOf(name);return i>=0?args[i+1]:fallback;};
const sourcePath=path.resolve(root,value('--existing-catalog','build/private-source/catalog-production-2026-09-12.json'));
const curationPath=path.resolve(root,value('--curation','catalog/curation-v1.json'));
const outputPath=path.resolve(root,value('--output','catalog/target-plan.json'));

const readJson=file=>JSON.parse(fs.readFileSync(file,'utf8'));
const slug=value=>String(value).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase()
  .replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,72);
const uniqueIds=works=>{
  const seen=new Map();
  for(const work of works){
    const base=work.id||`${work.type}-${slug(work.title)}`;
    const n=(seen.get(base)||0)+1;seen.set(base,n);
    work.id=n===1?base:`${base}-${n}`;
  }
  return works;
};

const legacy=readJson(sourcePath);
const curation=readJson(curationPath);
const manga=legacy.works.filter(work=>work.type==='manga').map(work=>({
  id:work.id,
  title:work.displayTitle||work.canonicalTitle,
  type:'manga',
  editionCount:Array.isArray(work.editions)?work.editions.length:0,
  catalogStatus:'existing-normalized',
  coverStatus:'source-review-required'
}));
const books=curation.books.map(work=>({
  title:work.title,alternateTitle:work.alternateTitle,author:work.author,type:'book',
  editionCount:0,catalogStatus:'source-match-required',coverStatus:'source-review-required'
}));
const families=curation.hqFamilies.map(title=>({
  title,type:'hq',editorialGroup:'family',editionCount:0,
  catalogStatus:'source-inventory-required',coverStatus:'source-review-required'
}));
const sagas=curation.dcSagas.map(title=>({
  title,type:'hq',editorialGroup:'Grandes Sagas DC',editionCount:0,
  catalogStatus:'source-inventory-required',coverStatus:'source-review-required'
}));
const magazines=curation.magazines.map(work=>({
  title:work.title,type:'magazine',sections:[work.section],editionCount:0,
  catalogStatus:'source-inventory-required',coverStatus:'source-review-required'
}));
const works=uniqueIds([...manga,...books,...families,...sagas,...magazines]);
const counts=Object.fromEntries(['manga','book','hq','magazine'].map(type=>[type,works.filter(w=>w.type===type).length]));
const expected={manga:188,book:60,hq:87,magazine:1};
for(const [type,count] of Object.entries(expected)){
  if(counts[type]!==count)throw new Error(`target ${type} count mismatch: ${counts[type]} != ${count}`);
}
if(new Set(works.map(w=>w.id)).size!==works.length)throw new Error('duplicate target IDs');
const payload={
  schemaVersion:1,
  generatedFrom:{legacyCatalogRevision:legacy.revision,curationSchemaVersion:curation.schemaVersion},
  counts:{...counts,total:works.length},
  works,
  exclusions:curation.excluded,
  expansionPriorities:curation.expansionPriorities
};
fs.mkdirSync(path.dirname(outputPath),{recursive:true});
fs.writeFileSync(outputPath,JSON.stringify(payload,null,2)+'\n');
console.log(JSON.stringify({ok:true,output:path.relative(root,outputPath),counts:payload.counts}));
