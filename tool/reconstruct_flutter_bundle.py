#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys

ROOT=Path(__file__).resolve().parents[1]
STAGING=ROOT/'staging'/'flutter-bundle'
manifest=json.loads((STAGING/'MANIFEST.json').read_text())
chunks=sorted(STAGING.glob('chunk-*.txt'))
expected_count=int(manifest['chunkCount'])
if len(chunks)!=expected_count:
    raise SystemExit(f'chunk count mismatch: {len(chunks)} != {expected_count}')
expected_names=[f'chunk-{i:03d}.txt' for i in range(int(manifest['firstChunk']),int(manifest['lastChunk'])+1)]
actual_names=[p.name for p in chunks]
if actual_names!=expected_names:
    raise SystemExit('chunk sequence mismatch')

correction=(STAGING/'CHUNK_068_CORRECTION.txt').read_text().strip()
if correction!='APPEND_ASCII_40':
    raise SystemExit('invalid chunk 068 correction marker')
parts=[]
for p in chunks:
    data=p.read_bytes()
    if p.name=='chunk-068.txt':
        data+=bytes([40])
    parts.append(data)
bundle=b''.join(parts)
if len(bundle)!=int(manifest['bundleBytes']):
    raise SystemExit(f'bundle size mismatch: {len(bundle)} != {manifest["bundleBytes"]}')
digest=hashlib.sha256(bundle).hexdigest()
if digest!=manifest['bundleSha256']:
    raise SystemExit(f'bundle sha256 mismatch: {digest}')

pos=0
magic=b'LUME_TEXT_BUNDLE_V1\n'
if not bundle.startswith(magic):
    raise SystemExit('invalid bundle magic')
pos=len(magic)
written=[]
header_re=re.compile(rb'FILE (\d+) (\d+)\n')
while pos<len(bundle):
    m=header_re.match(bundle,pos)
    if not m:
        raise SystemExit(f'invalid file header at byte {pos}')
    path_len=int(m.group(1)); data_len=int(m.group(2)); pos=m.end()
    raw_path=bundle[pos:pos+path_len]; pos+=path_len
    if len(raw_path)!=path_len or bundle[pos:pos+1]!=b'\n':
        raise SystemExit('truncated path record')
    pos+=1
    rel=raw_path.decode('utf-8')
    rel_path=Path(rel)
    if rel_path.is_absolute() or '..' in rel_path.parts or rel_path.parts[:1]!=('flutter',):
        raise SystemExit(f'unsafe bundle path: {rel}')
    data=bundle[pos:pos+data_len]; pos+=data_len
    if len(data)!=data_len or bundle[pos:pos+1]!=b'\n':
        raise SystemExit(f'truncated data record: {rel}')
    pos+=1
    target=(ROOT/rel_path).resolve()
    flutter_root=(ROOT/'flutter').resolve()
    if target!=flutter_root and flutter_root not in target.parents:
        raise SystemExit(f'path escaped flutter root: {rel}')
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(data)
    written.append(rel)

if len(written)!=int(manifest['sourceFiles']):
    raise SystemExit(f'source file count mismatch: {len(written)} != {manifest["sourceFiles"]}')
print(json.dumps({'ok':True,'bundleBytes':len(bundle),'bundleSha256':digest,'files':len(written)},indent=2))
