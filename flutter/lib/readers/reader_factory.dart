import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../models/progress.dart';
import 'pdf_reader_page.dart';
import 'epub_reader_page.dart';
import 'cbz_reader_page.dart';

Widget readerFor({
  required Edition edition,
  required String localPath,
  String? preparedEpubEntry,
  String? preparedEpubRoot,
  List<String>? preparedEpubSpine,
  bool epubFixedLayout = false,
  List<String>? preparedCbzPages,
  ReadingLocator? locator,
  ValueChanged<ReadingLocator>? onProgress,
}) {
  switch (edition.format.toLowerCase()) {
    case 'pdf':
      return PdfReaderPage(
        localPath: localPath,
        initial: locator is PageLocator ? locator : null,
        onProgress: onProgress,
      );
    case 'epub':
      if (preparedEpubEntry == null || preparedEpubEntry.isEmpty || preparedEpubRoot == null || preparedEpubRoot.isEmpty) {
        return const Scaffold(body: Center(child: Text('EPUB ainda não foi preparado para leitura.')));
      }
      final initial = locator is EpubLocator ? locator : EpubLocator('', progression: 0);
      return EpubReaderPage(
        localEntry: Uri.file(preparedEpubEntry),
        rootPath: preparedEpubRoot,
        spineEntries: preparedEpubSpine ?? const [],
        initial: initial,
        onProgress: onProgress,
        fixedLayout: epubFixedLayout,
      );
    case 'cbz':
      final pages=preparedCbzPages ?? const [];
      if(pages.isEmpty){
        return const Scaffold(body:Center(child:Text('CBZ ainda não foi preparado para leitura.')));
      }
      return CbzReaderPage(
        pages:pages,
        initial:locator is PageLocator ? locator : null,
        onProgress:onProgress,
      );
    case 'cbr':
      return Scaffold(
        appBar:AppBar(title:const Text('CBR não disponível')),
        body:const Center(child:Padding(
          padding:EdgeInsets.all(24),
          child:Text(
            'Esta edição usa CBR/RAR. A LUME não abrirá o arquivo até que a extração RAR seja validada com segurança neste dispositivo.',
            textAlign:TextAlign.center,
          ),
        )),
      );
    default:
      return Scaffold(
        appBar: AppBar(title: const Text('Formato não suportado')),
        body: Center(child: Text('Formato ${edition.format} ainda não possui leitor.')),
      );
  }
}
