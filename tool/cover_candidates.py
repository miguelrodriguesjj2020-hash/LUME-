#!/usr/bin/env python3
"""Render contact sheets so a human reviews cover candidates before extraction."""

from __future__ import annotations

import argparse
import io
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image,ImageDraw,ImageOps,UnidentifiedImageError

from normalize_media import ARCHIVE_EXTENSIONS,NormalizationError,archive_images,extract_epub_cover,natural_key,sha256_file


def _pdf_pages(source:Path,limit:int)->list[tuple[str,bytes]]:
    executable=shutil.which("pdftoppm") or shutil.which("pdftocairo")
    if not executable:raise NormalizationError("pdftoppm or pdftocairo is required")
    with tempfile.TemporaryDirectory(prefix="lume-candidates-") as directory:
        base=Path(directory)/"page"
        process=subprocess.run([executable,"-f","1","-l",str(limit),"-jpeg","-scale-to","1200",str(source),str(base)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
        paths=sorted(Path(directory).glob("page-*.jpg"),key=lambda p:natural_key(p.name))
        if process.returncode!=0 or not paths:
            raise NormalizationError(f"could not render PDF candidates: {process.stderr.decode('utf-8','replace').strip()}")
        return [(p.name,p.read_bytes()) for p in paths]


def source_pages(source:Path,limit:int)->tuple[list[tuple[str,bytes]],int|None]:
    suffix=source.suffix.casefold()
    if source.is_dir() or suffix in ARCHIVE_EXTENSIONS:
        pages=archive_images(source);return pages[:limit],len(pages)
    if suffix==".pdf":return _pdf_pages(source,limit),None
    if suffix==".epub":
        data,extension=extract_epub_cover(source);return [(f"embedded-cover{extension}",data)],1
    raise NormalizationError(f"unsupported media input: {source.name}")


def _rgb(data:bytes)->Image.Image:
    try:
        image=ImageOps.exif_transpose(Image.open(io.BytesIO(data)))
        if image.mode in {"RGBA","LA"}:
            background=Image.new("RGB",image.size,"white");background.paste(image,mask=image.getchannel("A"));return background
        return image.convert("RGB")
    except (OSError,UnidentifiedImageError) as exc:raise NormalizationError("could not decode cover candidate") from exc


def render_candidates(source:Path,output:Path,limit:int=12,columns:int=4)->dict[str,object]:
    if not source.exists():raise NormalizationError(f"source does not exist: {source}")
    if not 1<=limit<=24:raise NormalizationError("candidate limit must be between 1 and 24")
    if not 1<=columns<=6:raise NormalizationError("columns must be between 1 and 6")
    pages,count=source_pages(source,limit)
    if not pages:raise NormalizationError(f"no candidate pages in {source.name}")
    output.parent.mkdir(parents=True,exist_ok=True)
    preview_dir=output.parent/f"{output.stem}-pages";preview_dir.mkdir(parents=True,exist_ok=True)
    cell_width,cell_height=260,370;rows=(len(pages)+columns-1)//columns
    sheet=Image.new("RGB",(columns*cell_width,rows*cell_height),"#f2eee4");draw=ImageDraw.Draw(sheet);candidates=[]
    for index,(name,data) in enumerate(pages,1):
        image=_rgb(data);image.thumbnail((230,315),Image.Resampling.LANCZOS)
        preview=preview_dir/f"page-{index:03d}.jpg";image.save(preview,"JPEG",quality=86,optimize=True,progressive=True)
        column=(index-1)%columns;row=(index-1)//columns;x=column*cell_width+(cell_width-image.width)//2;y=row*cell_height+10
        sheet.paste(image,(x,y));draw.text((column*cell_width+12,row*cell_height+338),f"PÁGINA {index:02d} · {Path(name).name[:28]}",fill="#101310")
        candidates.append({"page":index,"sourceName":name,"previewPath":str(preview)})
    sheet.save(output,"JPEG",quality=88,optimize=True,progressive=True)
    return {"source":str(source),"sourceSha256":sha256_file(source) if source.is_file() else None,"sourcePageCount":count,"candidateCount":len(candidates),"contactSheetPath":str(output),"candidates":candidates}


def main(argv:list[str]|None=None)->int:
    parser=argparse.ArgumentParser(description="Create a LUME cover candidate contact sheet")
    parser.add_argument("source",type=Path);parser.add_argument("--output",type=Path,required=True);parser.add_argument("--limit",type=int,default=12);parser.add_argument("--columns",type=int,default=4);parser.add_argument("--manifest",type=Path)
    args=parser.parse_args(argv)
    try:result=render_candidates(args.source,args.output,args.limit,args.columns)
    except NormalizationError as exc:
        print(json.dumps({"ok":False,"error":str(exc)},ensure_ascii=False),file=sys.stderr);return 2
    payload={"ok":True,**result};rendered=json.dumps(payload,ensure_ascii=False,indent=2)+"\n"
    if args.manifest:args.manifest.parent.mkdir(parents=True,exist_ok=True);args.manifest.write_text(rendered,encoding="utf-8")
    print(rendered,end="");return 0


if __name__=="__main__":raise SystemExit(main())

