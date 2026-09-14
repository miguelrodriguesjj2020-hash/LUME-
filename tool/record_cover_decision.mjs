#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const args=process.argv.slice(2);
const value=(name,{required=false}={})=>{
  const index=args.indexOf(name);
  if(index<0){if(required)throw new Error(`${name} is required`);return null;}
  if(index===args.length-1)throw new Error(`${name} requires a value`);
  return args[index+1];
};
const positiveInt=(name)=>{const parsed=Number(value(name,{required:true}));if(!Number.isInteger(parsed)||parsed<1)throw new Error(`${name} must be a positive integer`);return parsed;};
const hash=(raw,label)=>{if(typeof raw!=='string'||!/^[a-f0-9]{64}$/i.test(raw))throw new Error(`${label} must be SHA-256 hex`);return raw.toLowerCase();};

function summarize(decisions){
  const attempts=decisions.flatMap(d=>d.attempts||[]);
  return {
    worksReviewed:decisions.length,
    sourceFilesInspected:attempts.length,
    coversAcceptedLocal:decisions.filter(d=>d.status==='accepted-local').length,
    replacementSourcesRequired:decisions.filter(d=>d.status==='replacement-source-required').length,
    coversUploaded:decisions.filter(d=>d.status==='uploaded').length,
  };
}

function atomicJson(file,payload){
  fs.mkdirSync(path.dirname(file),{recursive:true});
  const temporary=path.join(path.dirname(file),`.${path.basename(file)}.${process.pid}.${Date.now()}.tmp`);
  fs.writeFileSync(temporary,JSON.stringify(payload,null,2)+'\n',{mode:0o600});
  fs.renameSync(temporary,file);
}

function main(){
  const ledgerPath=path.resolve(value('--ledger',{required:true}));
  const workId=value('--work-id',{required:true});
  const title=value('--title',{required:true});
  const status=value('--status',{required:true});
  if(!['accepted-local','replacement-source-required','uploaded'].includes(status))throw new Error('invalid status');
  if(!/^[a-z0-9][a-z0-9-]{1,95}$/.test(workId))throw new Error('invalid work ID');
  const sourceFileName=value('--source-file-name',{required:true});
  const inspectedPages=positiveInt('--inspected-pages');
  const qualityNote=value('--quality-note',{required:true});
  if(!qualityNote.trim())throw new Error('quality note cannot be empty');
  const manifestPath=value('--manifest');
  const manifest=manifestPath?JSON.parse(fs.readFileSync(path.resolve(manifestPath),'utf8')):null;
  const sourceSha256=hash(manifest?.sourceSha256||value('--source-sha256',{required:!manifest}),'source hash');
  const attempt={sourceFileName,sourceSha256,inspectedPages,qualityNote:qualityNote.trim()};
  if(manifest){
    if(manifest.id!==workId)throw new Error('manifest work ID mismatch');
    if(manifest.ok!==true)throw new Error('manifest is not successful');
    attempt.selectedPage=manifest.coverPage;
  }
  const decision={workId,title,status,attempts:[]};
  if(status!=='replacement-source-required'){
    if(!manifest)throw new Error('accepted/uploaded status requires a normalization manifest');
    decision.cover={
      fileName:path.basename(manifest.coverPath),
      byteSize:Number(manifest.coverBytes),
      sha256:hash(manifest.coverSha256,'cover hash'),
      mimeType:'image/jpeg',
      selectedPage:Number(manifest.coverPage),
      cropFractions:manifest.cropFractions,
      trimBackground:Boolean(manifest.trimBackground),
      localOnly:status==='accepted-local'
    };
  }
  const reviewKind=value('--review-kind');const reviewReason=value('--review-reason');
  if(reviewKind||reviewReason){
    if(!reviewKind||!reviewReason)throw new Error('review kind and reason must be supplied together');
    decision.review={kind:reviewKind,reason:reviewReason,status:'required'};
  }
  const ledger=fs.existsSync(ledgerPath)?JSON.parse(fs.readFileSync(ledgerPath,'utf8')):{schemaVersion:2,decisions:[]};
  if(ledger.schemaVersion!==2||!Array.isArray(ledger.decisions))throw new Error('unsupported ledger schema');
  const index=ledger.decisions.findIndex(item=>item.workId===workId);
  if(index>=0){
    const prior=ledger.decisions[index];
    decision.attempts=[...(prior.attempts||[]).filter(item=>item.sourceSha256!==sourceSha256),attempt];
    if(!decision.review && prior.review)decision.review=prior.review;
    ledger.decisions[index]=decision;
  }else{
    decision.attempts=[attempt];ledger.decisions.push(decision);
  }
  ledger.decisions.sort((a,b)=>a.workId.localeCompare(b.workId,'en'));
  ledger.summary=summarize(ledger.decisions);
  atomicJson(ledgerPath,ledger);
  console.log(JSON.stringify({ok:true,workId,status,summary:ledger.summary}));
}

try{main();}catch(error){console.error(JSON.stringify({ok:false,error:error.message||String(error),host:os.platform()}));process.exitCode=2;}

