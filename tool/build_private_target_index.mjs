#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');

export function naturalParts(value){
  return String(value).normalize('NFKD').toLowerCase().split(/(\d+(?:[.,]\d+)?)/)
    .filter(Boolean).map(part=>/^\d/.test(part)?Number(part.replace(',','.')):part);
}

export function naturalCompare(a,b){
  const aa=naturalParts(a),bb=naturalParts(b);
  for(let i=0;i<Math.max(aa.length,bb.length);i++){
    if(i>=aa.length)return -1;if(i>=bb.length)return 1;
    if(aa[i]===bb[i])continue;
    if(typeof aa[i]===typeof bb[i])return aa[i]<bb[i]?-1:1;
    return typeof aa[i]==='number'?-1:1;
  }
  return 0;
}

export function sequenceNumber(edition){
  for(const value of [edition.volumeNumber,edition.chapterNumber]){
    if(typeof value==='number' && Number.isFinite(value))return value;
  }
  const stem=path.basename(String(edition.fileName||''),path.extname(String(edition.fileName||'')));
  const pure=stem.match(/^\s*(\d+(?:[.,]\d+)?)\s*$/);
  if(pure)return Number(pure[1].replace(',','.'));
  const labeled=stem.match(/(?:vol(?:ume)?|cap(?:[íi]tulo)?|chapter|ch)[\s._-]*(\d+(?:[.,]\d+)?)/i);
  if(labeled)return Number(labeled[1].replace(',','.'));
  const any=stem.match(/(?:^|\D)(\d+(?:[.,]\d+)?)(?:\D|$)/);
  return any?Number(any[1].replace(',','.')):Number.POSITIVE_INFINITY;
}

export function chooseCoverSource(editions){
  const supported=editions.filter(e=>['pdf','cbz'].includes(String(e.format).toLowerCase()) && e.sourceFileId && e.fileName);
  return [...supported].sort((a,b)=>{
    const sa=sequenceNumber(a),sb=sequenceNumber(b);
    if(sa!==sb)return sa-sb;
    const formatA=a.format==='cbz'?0:1,formatB=b.format==='cbz'?0:1;
    if(formatA!==formatB)return formatA-formatB;
    return naturalCompare(a.fileName,b.fileName);
  })[0]||null;
}

export function buildPrivateIndex(plan,legacy){
  const legacyById=new Map(legacy.works.map(work=>[work.id,work]));
  const works=plan.works.map(work=>{
    if(work.type!=='manga')return {...work};
    const source=legacyById.get(work.id);
    if(!source)throw new Error(`legacy manga missing: ${work.id}`);
    const candidate=chooseCoverSource(source.editions||[]);
    return {
      ...work,
      sourceFolderIds:source.sourceFolderIds||[],
      coverStatus:candidate?'source-candidate-ready':'replacement-source-required',
      ...(candidate?{coverSourceCandidate:{
        editionId:candidate.id,
        sourceFileId:candidate.sourceFileId,
        fileName:candidate.fileName,
        format:String(candidate.format).toLowerCase(),
        byteSize:candidate.byteSize??null
      }}:{}),
    };
  });
  return {...plan,privateIndex:true,works};
}

function main(){
  const args=process.argv.slice(2);
  const value=(name,fallback)=>{const i=args.indexOf(name);return i>=0?args[i+1]:fallback;};
  const plan=JSON.parse(fs.readFileSync(path.resolve(root,value('--plan','catalog/target-plan.json')),'utf8'));
  const legacy=JSON.parse(fs.readFileSync(path.resolve(root,value('--existing-catalog','build/private-source/catalog-production-2026-09-12.json')),'utf8'));
  const output=path.resolve(root,value('--output','build/private-target-index.json'));
  const payload=buildPrivateIndex(plan,legacy);
  const manga=payload.works.filter(w=>w.type==='manga');
  if(manga.length!==188)throw new Error(`expected 188 manga, got ${manga.length}`);
  fs.mkdirSync(path.dirname(output),{recursive:true});
  fs.writeFileSync(output,JSON.stringify(payload,null,2)+'\n');
  console.log(JSON.stringify({
    ok:true,
    works:payload.works.length,
    mangaCandidates:manga.filter(w=>w.coverSourceCandidate).length,
    replacementSourcesRequired:manga.filter(w=>!w.coverSourceCandidate).length,
    output:path.relative(root,output)
  }));
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main();

