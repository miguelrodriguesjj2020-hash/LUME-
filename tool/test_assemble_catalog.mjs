#!/usr/bin/env node
import test from 'node:test';
import assert from 'node:assert/strict';
import { assembleCatalog } from './assemble_catalog.mjs';

const cover={sourceFileId:'cover-source',fileName:'cover.jpg',mimeType:'image/jpeg',byteSize:200,sha256:'a'.repeat(64)};
const edition={id:'edition-1',sourceFileId:'media-source',fileName:'volume.pdf',format:'pdf',sha256:'b'.repeat(64)};
const target={counts:{total:1},works:[{id:'manga-one',title:'One',type:'manga',editionCount:1}]};
const inventory={works:[{id:'manga-one',cover,editions:[edition]}]};
const ledger={decisions:[{workId:'manga-one',status:'uploaded',cover:{sha256:cover.sha256}}]};

test('assembler emits only a complete approved target',()=>{
  const result=assembleCatalog({target,inventory,ledger,revision:2,generatedAt:'2026-09-14T00:00:00Z'});
  assert.equal(result.works.length,1);assert.equal(result.works[0].cover.sha256,cover.sha256);assert.equal(result.revision,2);
});

test('assembler blocks missing or merely local covers',()=>{
  assert.throws(()=>assembleCatalog({target,inventory,ledger:{decisions:[]},revision:2}),/uploaded cover decision missing/);
  assert.throws(()=>assembleCatalog({target,inventory,ledger:{decisions:[{...ledger.decisions[0],status:'accepted-local'}]},revision:2}),/uploaded cover decision missing/);
});

test('assembler blocks cover hash substitution',()=>{
  assert.throws(()=>assembleCatalog({target,inventory:{works:[{...inventory.works[0],cover:{...cover,sha256:'c'.repeat(64)}}]},ledger,revision:2}),/cover hash mismatch/);
});

test('assembler blocks CBR and empty works',()=>{
  assert.throws(()=>assembleCatalog({target,inventory:{works:[{...inventory.works[0],editions:[{...edition,format:'cbr'}]}]},ledger,revision:2}),/unsupported format/);
  assert.throws(()=>assembleCatalog({target,inventory:{works:[{...inventory.works[0],editions:[]}]},ledger,revision:2}),/no readable editions/);
});

test('assembler blocks extra and missing inventory',()=>{
  assert.throws(()=>assembleCatalog({target,inventory:{works:[]},ledger,revision:2}),/inventory missing/);
  assert.throws(()=>assembleCatalog({target,inventory:{works:[...inventory.works,{id:'extra',cover,editions:[{...edition,id:'e2'}]}]},ledger,revision:2}),/non-target works/);
});
