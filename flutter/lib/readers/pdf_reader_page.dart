import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../models/progress.dart';

class PdfReaderPage extends StatefulWidget {
  final String localPath;
  final PageLocator? initial;
  final ValueChanged<PageLocator>? onProgress;
  const PdfReaderPage({super.key, required this.localPath, this.initial, this.onProgress});

  @override State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  late PdfControllerPinch controller;
  int page = 1;
  int? pageCount;

  @override void initState() {
    super.initState();
    page = (widget.initial?.page ?? 1) < 1 ? 1 : (widget.initial?.page ?? 1);
    controller = PdfControllerPinch(document: PdfDocument.openFile(widget.localPath), initialPage: page);
  }

  void _emit(int newPage) {
    page = newPage;
    widget.onProgress?.call(PageLocator(page, pageCount: pageCount));
  }

  @override Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(pageCount == null ? 'Página $page' : 'Página $page de $pageCount')),
        body: PdfViewPinch(
          controller: controller,
          onDocumentLoaded: (doc) {
            final count=doc.pagesCount;
            final clamped=page>count ? count : page;
            setState(() { pageCount=count; page=clamped; });
            if(clamped != widget.initial?.page) {
              controller.jumpToPage(clamped);
              _emit(clamped);
            }
          },
          onPageChanged: _emit,
        ),
      );

  @override void dispose() {
    controller.dispose();
    super.dispose();
  }
}
