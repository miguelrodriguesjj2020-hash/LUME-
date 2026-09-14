import 'dart:io';
import 'package:flutter/material.dart';
import '../models/progress.dart';

class CbzReaderPage extends StatefulWidget {
  final List<String> pages;
  final PageLocator? initial;
  final ValueChanged<PageLocator>? onProgress;
  const CbzReaderPage({super.key,required this.pages,this.initial,this.onProgress});
  @override State<CbzReaderPage> createState()=>_CbzReaderPageState();
}

class _CbzReaderPageState extends State<CbzReaderPage> {
  late final PageController controller;
  late int pageIndex;

  @override void initState(){
    super.initState();
    final requested=(widget.initial?.page ?? 1)-1;
    pageIndex=requested.clamp(0,widget.pages.length-1).toInt();
    controller=PageController(initialPage:pageIndex);
  }

  void _changed(int index){
    setState(()=>pageIndex=index);
    widget.onProgress?.call(PageLocator(index+1,pageCount:widget.pages.length));
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('Página ${pageIndex+1} de ${widget.pages.length}')),
    body:PageView.builder(
      controller:controller,
      onPageChanged:_changed,
      itemCount:widget.pages.length,
      itemBuilder:(_,i)=>InteractiveViewer(
        minScale:1,
        maxScale:4,
        child:Center(child:Image.file(
          File(widget.pages[i]),
          fit:BoxFit.contain,
          gaplessPlayback:true,
          filterQuality:FilterQuality.medium,
          errorBuilder:(_,__,___)=>const Center(child:Text('Não foi possível renderizar esta página.')),
        )),
      ),
    ),
  );

  @override void dispose(){controller.dispose();super.dispose();}
}
