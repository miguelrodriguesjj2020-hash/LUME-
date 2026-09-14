#!/usr/bin/env node
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const tool=new URL('./record_cover_decision.mjs',import.meta.url);
const run=(args)=>spawnSync(process.execPath,[tool.pathname,...args],{encoding:'utf8'});

test('accepted decision is atomically recorded without a Drive identifier',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'lume-ledger-'));
  const ledger=path.join(dir,'ledger.json');const manifest=path.join(dir,'manifest.json');
  fs.writeFileSync(manifest,JSON.stringify({ok:true,id:'manga-test',sourceSha256:'a'.repeat(64),coverPath:'/private/cover.jpg',coverBytes:1234,coverSha256:'b'.repeat(64),coverPage:2,cropFractions:[0,0,0,0],trimBackground:false}));
  const result=run(['--ledger',ledger,'--status','accepted-local','--work-id','manga-test','--title','Test','--source-file-name','VOL 01.pdf','--inspected-pages','12','--manifest',manifest,'--quality-note','Capa frontal confirmada.']);
  assert.equal(result.status,0,result.stderr);
  const saved=JSON.parse(fs.readFileSync(ledger));
  assert.deepEqual(saved.summary,{worksReviewed:1,sourceFilesInspected:1,coversAcceptedLocal:1,replacementSourcesRequired:0,coversUploaded:0});
  assert.equal(JSON.stringify(saved).includes('sourceFileId'),false);
  assert.equal(saved.decisions[0].cover.selectedPage,2);
});

test('alternate attempt replaces work outcome but remains auditable',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'lume-ledger-'));const ledger=path.join(dir,'ledger.json');
  const common=['--ledger',ledger,'--work-id','manga-test','--title','Test','--inspected-pages','8','--quality-note','Sem capa frontal válida.'];
  assert.equal(run([...common,'--status','replacement-source-required','--source-file-name','bad.pdf','--source-sha256','a'.repeat(64)]).status,0);
  const manifest=path.join(dir,'manifest.json');fs.writeFileSync(manifest,JSON.stringify({ok:true,id:'manga-test',sourceSha256:'b'.repeat(64),coverPath:'cover.jpg',coverBytes:300,coverSha256:'c'.repeat(64),coverPage:1,cropFractions:[0,0,0,0],trimBackground:false}));
  assert.equal(run(['--ledger',ledger,'--status','accepted-local','--work-id','manga-test','--title','Test','--source-file-name','good.pdf','--inspected-pages','8','--manifest',manifest,'--quality-note','Capa válida.']).status,0);
  const saved=JSON.parse(fs.readFileSync(ledger));
  assert.equal(saved.summary.sourceFilesInspected,2);assert.equal(saved.summary.coversAcceptedLocal,1);assert.equal(saved.decisions[0].attempts.length,2);
});

test('accepted decision fails closed without a successful manifest',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'lume-ledger-'));
  const result=run(['--ledger',path.join(dir,'ledger.json'),'--status','accepted-local','--work-id','manga-test','--title','Test','--source-file-name','x.pdf','--source-sha256','a'.repeat(64),'--inspected-pages','1','--quality-note','x']);
  assert.equal(result.status,2);assert.match(result.stderr,/requires a normalization manifest/);
});
