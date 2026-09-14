#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const ALLOWED_TYPES=new Set(['book','hq','manga','graphic_novel','magazine']);
const ALLOWED_FORMATS=new Set(['pdf','epub','cbz']);
const ALLOWED_COVER_MIMES=new Set(['image/jpeg','image/png','image/webp']);
const SHA256=/^[a-f0-9]{64}$/i;

function requiredText(value,label){if(typeof value!=='string'||!value.trim())throw new Error(`${label} is required`);return value.trim();}
function validateCover(cover,workId){
  if(!cover||typeof cover!=='object'||Array.isArray(cover))throw new Error(`cover missing for ${workId}`);
  requiredText(cover.sourceFileId,`cover sourceFileId for ${workId}`);requiredText(cover.fileName,`cover fileName for ${workId}`);
  if(!ALLOWED_COVER_MIMES.has(cover.mimeType))throw new Error(`invalid cover mimeType for ${workId}`);
  if(!Number.isInteger(cover.byteSize)||cover.byteSize<1)throw new Error(`invalid cover byteSize for ${workId}`);
  if(!SHA256.test(String(cover.sha256||'')))throw new Error(`invalid cover sha256 for ${workId}`);
}
function validateEditions(editions,workId,editionIds){
  if(!Array.isArray(editions)||editions.length<1)throw new Error(`no readable editions for ${workId}`);
  for(const edition of editions){
    const id=requiredText(edition.id,`edition id in ${workId}`);
    if(editionIds.has(id))throw new Error(`duplicate edition id: ${id}`);editionIds.add(id);
    if(!ALLOWED_FORMATS.has(edition.format))throw new Error(`unsupported format for ${id}: ${edition.format}`);
    requiredText(edition.sourceFileId,`sourceFileId for ${id}`);requiredText(edition.fileName,`fileName for ${id}`);
    if(edition.sha256!==undefined&&!SHA256.test(String(edition.sha256)))throw new Error(`invalid edition sha256 for ${id}`);
  }
}

export function assembleCatalog({target,inventory,ledger,revision,generatedAt}){
  if(!Number.isInteger(revision)||revision<1)throw new Error('revision must be a positive integer');
  if(!Array.isArray(target?.works)||!Number.isInteger(target?.counts?.total))throw new Error('invalid target plan');
  if(target.works.length!==target.counts.total)throw new Error('target total does not match target works');
  const inventoryById=new Map((inventory?.works||[]).map(work=>[work.id,work]));
  const decisionsById=new Map((ledger?.decisions||[]).map(decision=>[decision.workId,decision]));
  if(inventoryById.size!==(inventory?.works||[]).length)throw new Error('duplicate inventory work IDs');
  const targetIds=new Set(target.works.map(work=>work.id));
  const extra=[...inventoryById.keys()].filter(id=>!targetIds.has(id));
  if(extra.length)throw new Error(`inventory has non-target works: ${extra.join(', ')}`);
  const editionIds=new Set();
  const works=target.works.map(planned=>{
    const work=inventoryById.get(planned.id);if(!work)throw new Error(`inventory missing for ${planned.id}`);
    const decision=decisionsById.get(planned.id);if(!decision||decision.status!=='uploaded')throw new Error(`uploaded cover decision missing for ${planned.id}`);
    if(!ALLOWED_TYPES.has(planned.type))throw new Error(`invalid target type for ${planned.id}`);
    validateCover(work.cover,planned.id);
    if(String(decision.cover?.sha256||'').toLowerCase()!==String(work.cover.sha256).toLowerCase())throw new Error(`cover hash mismatch for ${planned.id}`);
    validateEditions(work.editions,planned.id,editionIds);
    return {
      id:planned.id,
      canonicalTitle:planned.title,
      displayTitle:planned.title,
      type:planned.type,
      ...(planned.author?{author:planned.author}:{}),
      ...(planned.alternateTitle?{alternateTitle:planned.alternateTitle}:{}),
      sourceFolderIds:Array.isArray(work.sourceFolderIds)?work.sourceFolderIds:[],
      sections:Array.isArray(work.sections)?work.sections:(Array.isArray(planned.sections)?planned.sections:[]),
      tags:Array.isArray(work.tags)?work.tags:[],
      cover:work.cover,
      editions:work.editions
    };
  });
  if(works.length!==target.counts.total)throw new Error(`assembled work count mismatch: ${works.length}`);
  return {revision,generatedAt:generatedAt||new Date().toISOString(),works,tombstones:[]};
}

function main(){
  const args=process.argv.slice(2);const value=(name,fallback)=>{const i=args.indexOf(name);return i>=0?args[i+1]:fallback;};
  const read=file=>JSON.parse(fs.readFileSync(path.resolve(root,file),'utf8'));
  const target=read(value('--target','catalog/target-plan.json'));
  const inventory=read(value('--inventory','build/private-production-inventory.json'));
  const ledger=read(value('--ledger','catalog/cover-decisions.json'));
  const revision=Number(value('--revision',String(inventory.revision||1)));
  const output=path.resolve(root,value('--output','build/catalog-production-v2.json'));
  const payload=assembleCatalog({target,inventory,ledger,revision,generatedAt:value('--generated-at',null)});
  fs.mkdirSync(path.dirname(output),{recursive:true});
  const temporary=`${output}.${process.pid}.tmp`;fs.writeFileSync(temporary,JSON.stringify(payload,null,2)+'\n',{mode:0o600});fs.renameSync(temporary,output);
  console.log(JSON.stringify({ok:true,revision,works:payload.works.length,editions:payload.works.reduce((n,w)=>n+w.editions.length,0),output:path.relative(root,output)}));
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{main();}catch(error){console.error(JSON.stringify({ok:false,error:error.message||String(error)}));process.exitCode=2;}
}

