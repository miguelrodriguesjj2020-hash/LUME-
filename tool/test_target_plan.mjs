#!/usr/bin/env node
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const curation=JSON.parse(fs.readFileSync(new URL('../catalog/curation-v1.json',import.meta.url)));

test('approved editorial curation has the frozen 336-work composition',()=>{
  assert.equal(curation.books.length,60);
  assert.equal(curation.hqFamilies.length,29);
  assert.equal(curation.dcSagas.length,58);
  assert.equal(curation.hqFamilies.length+curation.dcSagas.length,87);
  assert.equal(curation.magazines.length,1);
});

test('excluded adult titles never enter approved HQ arrays',()=>{
  const approved=new Set([...curation.hqFamilies,...curation.dcSagas].map(x=>x.toLowerCase()));
  for(const entry of curation.excluded)assert.equal(approved.has(entry.title.toLowerCase()),false);
});

test('expansion priorities are not counted as confirmed works',()=>{
  const confirmed=new Set([...curation.hqFamilies,...curation.dcSagas].map(x=>x.toLowerCase()));
  for(const title of curation.expansionPriorities)assert.equal(confirmed.has(title.toLowerCase()),false);
});
