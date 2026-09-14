from __future__ import annotations

import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import fitz
from PIL import Image

from cover_candidates import render_candidates
from normalize_media import NormalizationError,natural_key,normalize,parse_crop,sha256_file,zip_images


def image_bytes(color:str,size=(500,750))->bytes:
    output=io.BytesIO();Image.new("RGB",size,color).save(output,"JPEG");return output.getvalue()


class NormalizeMediaTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)

    def tearDown(self):self.temp.cleanup()

    def test_natural_page_order(self):
        self.assertEqual(sorted(["10.jpg","2.jpg","1.jpg"],key=natural_key),["1.jpg","2.jpg","10.jpg"])

    def test_folder_becomes_valid_cbz_and_cover(self):
        source=self.root/"pages";source.mkdir()
        (source/"2.jpg").write_bytes(image_bytes("blue"));(source/"1.jpg").write_bytes(image_bytes("red"))
        result=normalize(source,"sample-work",self.root/"out",1,(0,0,0,0),False,False)
        media=Path(result["mediaPath"]);self.assertEqual(media.suffix,".cbz");self.assertIsNone(zipfile.ZipFile(media).testzip())
        self.assertEqual(zipfile.ZipFile(media).namelist(),["page-00001.jpg","page-00002.jpg"])
        self.assertTrue(Path(result["coverPath"]).is_file())

    def test_cover_only_does_not_write_reading_media(self):
        source=self.root/"one.cbz"
        with zipfile.ZipFile(source,"w") as z:z.writestr("1.jpg",image_bytes("green"))
        result=normalize(source,"cover-only",self.root/"out",1,(0,0,0,0),False,True)
        self.assertNotIn("mediaPath",result);self.assertTrue(Path(result["coverPath"]).is_file())

    def test_pdf_selected_page_is_used(self):
        source=self.root/"book.pdf";doc=fitz.open()
        for color in ((1,0,0),(0,0,1)):
            page=doc.new_page(width=400,height=600);page.draw_rect(page.rect,color=color,fill=color)
        doc.save(source);doc.close()
        result=normalize(source,"pdf-work",self.root/"out",2,(0,0,0,0),False,True)
        self.assertEqual(result["coverPage"],2);self.assertEqual(result["sourceSha256"],sha256_file(source))

    def test_contact_sheet_never_selects_automatically(self):
        source=self.root/"pages";source.mkdir()
        for i in range(1,4):(source/f"{i}.jpg").write_bytes(image_bytes("white"))
        result=render_candidates(source,self.root/"sheet.jpg",limit=3,columns=2)
        self.assertEqual(result["candidateCount"],3);self.assertNotIn("selectedPage",result)

    def test_zip_path_traversal_is_rejected(self):
        source=self.root/"unsafe.cbz"
        with zipfile.ZipFile(source,"w") as z:z.writestr("../cover.jpg",image_bytes("red"))
        with self.assertRaisesRegex(NormalizationError,"unsafe archive path"):zip_images(source)

    def test_invalid_crop_is_rejected(self):
        with self.assertRaises(NormalizationError):parse_crop("0.6,0,0,0")
        with self.assertRaises(NormalizationError):parse_crop("0,0,0")

    def test_invalid_identifier_is_rejected(self):
        source=self.root/"pages";source.mkdir();(source/"1.jpg").write_bytes(image_bytes("red"))
        with self.assertRaisesRegex(NormalizationError,"identifier"):normalize(source,"Unsafe ID",self.root/"out",1,(0,0,0,0),False,True)

    def test_manifest_fields_are_json_serializable(self):
        source=self.root/"one.cbz"
        with zipfile.ZipFile(source,"w") as z:z.writestr("1.jpg",image_bytes("black"))
        result=normalize(source,"serializable",self.root/"out",1,(0,0,0,0),False,True)
        self.assertEqual(json.loads(json.dumps(result))["coverSha256"],sha256_file(Path(result["coverPath"])))


if __name__=="__main__":unittest.main()

