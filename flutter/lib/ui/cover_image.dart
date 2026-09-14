import 'dart:io';
import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../services/cover_cache.dart';

class WorkCoverImage extends StatelessWidget {
  final Work work;
  final CoverCache cache;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const WorkCoverImage({
    super.key,
    required this.work,
    required this.cache,
    this.borderRadius=const BorderRadius.all(Radius.circular(8)),
    this.fit=BoxFit.cover,
  });

  @override Widget build(BuildContext context)=>Hero(
    tag:'cover:${work.id}',
    child:ClipRRect(
      borderRadius:borderRadius,
      child:ColoredBox(
        color:Theme.of(context).colorScheme.surfaceContainerHighest,
        child:FutureBuilder<File?>(
          future:cache.resolve(work),
          builder:(context,snapshot){
            final file=snapshot.data;
            if(file!=null)return Image.file(file,fit:fit,filterQuality:FilterQuality.medium,errorBuilder:(_,__,___)=>_placeholder(context,failed:true));
            return _placeholder(context,failed:snapshot.hasError||snapshot.connectionState==ConnectionState.done);
          },
        ),
      ),
    ),
  );

  Widget _placeholder(BuildContext context,{required bool failed})=>Center(
    child:Semantics(
      label:failed?'Capa indisponível para ${work.title}':'Carregando capa de ${work.title}',
      child:Icon(failed?Icons.broken_image_outlined:Icons.auto_stories_outlined,color:Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
