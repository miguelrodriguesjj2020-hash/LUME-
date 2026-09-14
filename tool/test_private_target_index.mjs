#!/usr/bin/env node
import test from 'node:test';
import assert from 'node:assert/strict';
import { chooseCoverSource, sequenceNumber } from './build_private_target_index.mjs';

test('pure numeric filenames are valid sequence candidates',()=>{
  assert.equal(sequenceNumber({fileName:'1.1.cbz'}),1.1);
  assert.equal(sequenceNumber({fileName:'7.pdf'}),7);
});

test('explicit metadata wins over a later number in the filename',()=>{
  assert.equal(sequenceNumber({volumeNumber:1,fileName:'scan-2026.pdf'}),1);
});

test('candidate chooser finds earliest actually available edition',()=>{
  const selected=chooseCoverSource([
    {id:'e9',format:'pdf',sourceFileId:'s9',fileName:'9.pdf'},
    {id:'e7',format:'pdf',sourceFileId:'s7',fileName:'7.pdf'},
  ]);
  assert.equal(selected.id,'e7');
});

test('candidate chooser prefers CBZ when sequence is equal',()=>{
  const selected=chooseCoverSource([
    {id:'pdf',format:'pdf',sourceFileId:'p',fileName:'VOL 01.pdf'},
    {id:'cbz',format:'cbz',sourceFileId:'c',fileName:'1.cbz'},
  ]);
  assert.equal(selected.id,'cbz');
});

test('unsupported formats never become publication candidates',()=>{
  assert.equal(chooseCoverSource([{id:'rar',format:'cbr',sourceFileId:'r',fileName:'1.cbr'}]),null);
});
