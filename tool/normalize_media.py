#!/usr/bin/env python3
"""Normalize LUME reading media and extract a visually selected real cover."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree

from PIL import Image, ImageChops, ImageOps, UnidentifiedImageError


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}
ARCHIVE_EXTENSIONS = {".cbz", ".zip", ".cbr", ".rar"}
FINAL_READING_EXTENSIONS = {".pdf", ".epub", ".cbz"}
IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9-]{1,95}$")


class NormalizationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def natural_key(value: str) -> list[object]:
    return [float(piece.replace(",", ".")) if re.fullmatch(r"\d+(?:[.,]\d+)?", piece) else piece.casefold()
            for piece in re.split(r"(\d+(?:[.,]\d+)?)", value) if piece]


def _safe_archive_name(name: str) -> bool:
    path = PurePosixPath(name.replace("\\", "/"))
    return not path.is_absolute() and ".." not in path.parts and bool(path.name)


def _is_image(name: str) -> bool:
    return Path(name).suffix.casefold() in IMAGE_EXTENSIONS


def folder_images(folder: Path) -> list[tuple[str, bytes]]:
    pages=[]
    for path in folder.rglob("*"):
        if path.is_file() and _is_image(path.name):
            pages.append((path.relative_to(folder).as_posix(), path.read_bytes()))
    pages.sort(key=lambda item:natural_key(item[0]))
    if not pages:
        raise NormalizationError(f"no image pages in {folder.name}")
    return pages


def zip_images(source: Path) -> list[tuple[str, bytes]]:
    try:
        with zipfile.ZipFile(source) as archive:
            pages=[]
            for info in archive.infolist():
                if info.is_dir() or not _is_image(info.filename):
                    continue
                if not _safe_archive_name(info.filename):
                    raise NormalizationError(f"unsafe archive path: {info.filename}")
                if info.file_size > 80 * 1024 * 1024:
                    raise NormalizationError(f"oversized archive page: {info.filename}")
                pages.append((info.filename, archive.read(info)))
    except NormalizationError:
        raise
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        raise NormalizationError(f"invalid ZIP/CBZ: {source.name}") from exc
    pages.sort(key=lambda item:natural_key(item[0]))
    if not pages:
        raise NormalizationError(f"no image pages in {source.name}")
    return pages


class LibArchive:
    ARCHIVE_OK=0
    ARCHIVE_EOF=1

    def __init__(self) -> None:
        library=ctypes.util.find_library("archive")
        if not library:
            raise NormalizationError("libarchive is required for CBR/RAR")
        self.lib=ctypes.CDLL(library)
        self.lib.archive_read_new.restype=ctypes.c_void_p
        self.lib.archive_read_support_filter_all.argtypes=[ctypes.c_void_p]
        self.lib.archive_read_support_format_all.argtypes=[ctypes.c_void_p]
        self.lib.archive_read_open_filename.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t]
        self.lib.archive_read_next_header.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_void_p)]
        self.lib.archive_entry_pathname.argtypes=[ctypes.c_void_p]
        self.lib.archive_entry_pathname.restype=ctypes.c_char_p
        self.lib.archive_entry_size.argtypes=[ctypes.c_void_p]
        self.lib.archive_entry_size.restype=ctypes.c_longlong
        self.lib.archive_read_data.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_size_t]
        self.lib.archive_read_data.restype=ctypes.c_ssize_t
        self.lib.archive_read_free.argtypes=[ctypes.c_void_p]
        self.lib.archive_error_string.argtypes=[ctypes.c_void_p]
        self.lib.archive_error_string.restype=ctypes.c_char_p

    def images(self, source: Path) -> list[tuple[str,bytes]]:
        archive=self.lib.archive_read_new()
        if not archive:
            raise NormalizationError("could not allocate archive reader")
        try:
            self.lib.archive_read_support_filter_all(archive)
            self.lib.archive_read_support_format_all(archive)
            if self.lib.archive_read_open_filename(archive,os.fsencode(source),10240)!=self.ARCHIVE_OK:
                raise NormalizationError(self._error(archive,source))
            pages=[]
            entry=ctypes.c_void_p()
            while True:
                status=self.lib.archive_read_next_header(archive,ctypes.byref(entry))
                if status==self.ARCHIVE_EOF:
                    break
                if status!=self.ARCHIVE_OK:
                    raise NormalizationError(self._error(archive,source))
                raw=self.lib.archive_entry_pathname(entry)
                name=os.fsdecode(raw) if raw else ""
                size=int(self.lib.archive_entry_size(entry))
                if not _is_image(name):
                    continue
                if not _safe_archive_name(name):
                    raise NormalizationError(f"unsafe archive path: {name}")
                if size<0 or size>80*1024*1024:
                    raise NormalizationError(f"invalid archive page size: {name}")
                data=bytearray()
                buffer=ctypes.create_string_buffer(1024*1024)
                while len(data)<size:
                    read=self.lib.archive_read_data(archive,buffer,min(len(buffer),size-len(data)))
                    if read<0:
                        raise NormalizationError(self._error(archive,source))
                    if read==0:
                        break
                    data.extend(buffer.raw[:read])
                if len(data)!=size:
                    raise NormalizationError(f"truncated archive page: {name}")
                pages.append((name,bytes(data)))
        finally:
            self.lib.archive_read_free(archive)
        pages.sort(key=lambda item:natural_key(item[0]))
        if not pages:
            raise NormalizationError(f"no image pages in {source.name}")
        return pages

    def _error(self,archive: int,source: Path)->str:
        raw=self.lib.archive_error_string(archive)
        detail=raw.decode("utf-8","replace") if raw else "unknown libarchive error"
        return f"could not read {source.name}: {detail}"


def archive_images(source: Path) -> list[tuple[str,bytes]]:
    if source.is_dir():
        return folder_images(source)
    if source.suffix.casefold() in {".cbz",".zip"}:
        return zip_images(source)
    if source.suffix.casefold() in {".cbr",".rar"}:
        return LibArchive().images(source)
    raise NormalizationError(f"unsupported archive: {source.name}")


def _xml_root(data: bytes, label: str) -> ElementTree.Element:
    try:
        return ElementTree.fromstring(data)
    except ElementTree.ParseError as exc:
        raise NormalizationError(f"invalid EPUB {label}") from exc


def extract_epub_cover(source: Path) -> tuple[bytes,str]:
    try:
        with zipfile.ZipFile(source) as archive:
            container=_xml_root(archive.read("META-INF/container.xml"),"container")
            rootfile=next((node.attrib.get("full-path") for node in container.iter() if node.tag.endswith("rootfile")),None)
            if not rootfile or not _safe_archive_name(rootfile):
                raise NormalizationError("invalid EPUB rootfile")
            opf=_xml_root(archive.read(rootfile),"package")
            manifest={node.attrib.get("id"):node for node in opf.iter() if node.tag.endswith("item")}
            cover_item=next((node for node in manifest.values() if "cover-image" in node.attrib.get("properties","").split()),None)
            if cover_item is None:
                cover_id=next((node.attrib.get("content") for node in opf.iter() if node.tag.endswith("meta") and node.attrib.get("name")=="cover"),None)
                cover_item=manifest.get(cover_id)
            href=cover_item.attrib.get("href") if cover_item is not None else None
            if not href:
                raise NormalizationError("EPUB cover not declared")
            member=(PurePosixPath(rootfile).parent/PurePosixPath(href)).as_posix()
            if not _safe_archive_name(member) or not _is_image(member):
                raise NormalizationError("invalid EPUB cover path")
            return archive.read(member),Path(member).suffix.casefold()
    except (KeyError,OSError,zipfile.BadZipFile) as exc:
        raise NormalizationError(f"invalid EPUB: {source.name}") from exc


def _pdf_page(source: Path,page: int,scale: int=2400)->bytes:
    executable=shutil.which("pdftoppm") or shutil.which("pdftocairo")
    if not executable:
        raise NormalizationError("pdftoppm or pdftocairo is required")
    with tempfile.TemporaryDirectory(prefix="lume-pdf-") as directory:
        target=Path(directory)/"page"
        process=subprocess.run([executable,"-f",str(page),"-l",str(page),"-singlefile","-jpeg","-scale-to",str(scale),str(source),str(target)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
        rendered=target.with_suffix(".jpg")
        if process.returncode!=0 or not rendered.is_file():
            message=process.stderr.decode("utf-8","replace").strip()
            raise NormalizationError(f"could not render PDF page {page}: {message}")
        return rendered.read_bytes()


def source_page(source: Path,page: int)->tuple[bytes,str]:
    if page<1:
        raise NormalizationError("cover page must be one-based")
    suffix=source.suffix.casefold()
    if source.is_dir() or suffix in ARCHIVE_EXTENSIONS:
        pages=archive_images(source)
        if page>len(pages):raise NormalizationError(f"cover page {page} exceeds {len(pages)} pages")
        name,data=pages[page-1]
        return data,Path(name).suffix.casefold()
    if suffix==".pdf":return _pdf_page(source,page),".jpg"
    if suffix==".epub":
        if page!=1:raise NormalizationError("EPUB exposes only its declared cover")
        return extract_epub_cover(source)
    raise NormalizationError(f"unsupported source format: {suffix or 'folder'}")


def _decode_image(data: bytes)->Image.Image:
    try:
        image=ImageOps.exif_transpose(Image.open(io.BytesIO(data)))
        if image.mode in {"RGBA","LA"}:
            base=Image.new("RGB",image.size,"white")
            base.paste(image,mask=image.getchannel("A"))
            return base
        return image.convert("RGB")
    except (OSError,UnidentifiedImageError) as exc:
        raise NormalizationError("could not decode selected cover") from exc


def parse_crop(value: str)->tuple[float,float,float,float]:
    try:parts=tuple(float(piece.strip()) for piece in value.split(","))
    except ValueError as exc:raise NormalizationError("crop fractions must be numeric") from exc
    if len(parts)!=4 or any(x<0 or x>=0.5 for x in parts):
        raise NormalizationError("crop fractions must be top,right,bottom,left values between 0 and 0.5")
    top,right,bottom,left=parts
    if top+bottom>=0.8 or left+right>=0.8:
        raise NormalizationError("crop fractions remove too much of the cover")
    return top,right,bottom,left


def _trim_white(image: Image.Image)->Image.Image:
    background=Image.new("RGB",image.size,"white")
    diff=ImageChops.difference(image,background).convert("L").point(lambda p:255 if p>14 else 0)
    bbox=diff.getbbox()
    if not bbox:return image
    left,top,right,bottom=bbox
    margin_x=min(12,max(2,image.width//300));margin_y=min(12,max(2,image.height//300))
    box=(max(0,left-margin_x),max(0,top-margin_y),min(image.width,right+margin_x),min(image.height,bottom+margin_y))
    if box[2]-box[0]<image.width*.55 or box[3]-box[1]<image.height*.55:return image
    return image.crop(box)


def write_cover(data: bytes,destination: Path,crop: tuple[float,float,float,float],trim: bool)->dict[str,object]:
    image=_decode_image(data)
    top,right,bottom,left=crop
    box=(round(image.width*left),round(image.height*top),round(image.width*(1-right)),round(image.height*(1-bottom)))
    image=image.crop(box)
    if trim:image=_trim_white(image)
    if image.width<120 or image.height<160:raise NormalizationError("selected cover is too small")
    image.thumbnail((1600,2400),Image.Resampling.LANCZOS)
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=destination.stem+"-",suffix=".jpg",dir=destination.parent,delete=False) as handle:
        temporary=Path(handle.name)
    try:
        image.save(temporary,"JPEG",quality=88,optimize=True,progressive=True)
        os.replace(temporary,destination)
    finally:
        temporary.unlink(missing_ok=True)
    return {"coverPath":str(destination),"coverBytes":destination.stat().st_size,"coverSha256":sha256_file(destination)}


def _write_cbz(pages:list[tuple[str,bytes]],destination:Path)->None:
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=destination.stem+"-",suffix=".cbz",dir=destination.parent,delete=False) as handle:
        temporary=Path(handle.name)
    try:
        with zipfile.ZipFile(temporary,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
            for index,(name,data) in enumerate(pages,1):
                extension=Path(name).suffix.casefold()
                if extension==".jpeg":extension=".jpg"
                archive.writestr(f"page-{index:05d}{extension}",data)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:raise NormalizationError("generated CBZ failed integrity check")
        os.replace(temporary,destination)
    finally:
        temporary.unlink(missing_ok=True)


def normalize(source:Path,identifier:str,output_dir:Path,cover_page:int,crop:tuple[float,float,float,float],trim:bool,cover_only:bool)->dict[str,object]:
    if not IDENTIFIER.fullmatch(identifier):raise NormalizationError("invalid LUME identifier")
    if not source.exists():raise NormalizationError(f"source does not exist: {source}")
    source_hash=sha256_file(source) if source.is_file() else None
    suffix=source.suffix.casefold()
    result={"ok":True,"id":identifier,"mode":"cover-only" if cover_only else "media-and-cover","source":str(source),"sourceFormat":suffix.lstrip(".") or "folder","coverPage":cover_page,"cropFractions":list(crop),"trimBackground":trim,"sourceSha256":source_hash}
    if not cover_only:
        media_dir=output_dir/"media";media_dir.mkdir(parents=True,exist_ok=True)
        if source.is_dir() or suffix in {".cbr",".rar",".zip"}:
            media=media_dir/f"{identifier}.cbz";_write_cbz(archive_images(source),media)
        elif suffix==".cbz":
            zip_images(source);media=media_dir/f"{identifier}.cbz";shutil.copyfile(source,media)
        elif suffix in {".pdf",".epub"}:
            if suffix==".pdf":_pdf_page(source,1,400)
            else:extract_epub_cover(source)
            media=media_dir/f"{identifier}{suffix}";shutil.copyfile(source,media)
        else:raise NormalizationError(f"unsupported source format: {suffix}")
        result.update({"mediaPath":str(media),"mediaFormat":media.suffix.lstrip("."),"mediaBytes":media.stat().st_size,"mediaSha256":sha256_file(media)})
    data,_=source_page(source,cover_page)
    result.update(write_cover(data,output_dir/"covers"/f"{identifier}.jpg",crop,trim))
    return result


def atomic_json(path:Path,payload:dict[str,object])->None:
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile("w",encoding="utf-8",prefix=path.name+"-",suffix=".tmp",dir=path.parent,delete=False) as handle:
        json.dump(payload,handle,ensure_ascii=False,indent=2);handle.write("\n");temporary=Path(handle.name)
    os.replace(temporary,path)


def main(argv:list[str]|None=None)->int:
    parser=argparse.ArgumentParser(description="Normalize LUME media and extract its real cover")
    parser.add_argument("source",type=Path);parser.add_argument("--id",required=True)
    parser.add_argument("--output-dir",type=Path,default=Path("build/normalized"));parser.add_argument("--manifest",type=Path)
    parser.add_argument("--cover-only",action="store_true");parser.add_argument("--cover-page",type=int,required=True)
    parser.add_argument("--crop-fractions",default="0,0,0,0");parser.add_argument("--trim-background",action="store_true")
    args=parser.parse_args(argv)
    try:payload=normalize(args.source,args.id,args.output_dir,args.cover_page,parse_crop(args.crop_fractions),args.trim_background,args.cover_only)
    except NormalizationError as exc:
        print(json.dumps({"ok":False,"error":str(exc)},ensure_ascii=False),file=sys.stderr);return 2
    if args.manifest:atomic_json(args.manifest,payload)
    print(json.dumps(payload,ensure_ascii=False,indent=2));return 0


if __name__=="__main__":raise SystemExit(main())
