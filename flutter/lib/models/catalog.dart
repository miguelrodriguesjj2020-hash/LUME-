class Edition {
  final String id, workId, format, sourceFileId, fileName, language;
  final int? byteSize;
  final double? volume, chapter;
  const Edition({
    required this.id,
    required this.workId,
    required this.format,
    required this.sourceFileId,
    required this.fileName,
    this.language='unknown',
    this.byteSize,
    this.volume,
    this.chapter,
  });
  factory Edition.fromJson(String workId, Map<String,dynamic> j)=>Edition(
    id:j['id'],
    workId:workId,
    format:j['format'],
    sourceFileId:j['sourceFileId'],
    fileName:j['fileName'],
    language:j['language']??'unknown',
    byteSize:j['byteSize'],
    volume:(j['volumeNumber'] as num?)?.toDouble(),
    chapter:(j['chapterNumber'] as num?)?.toDouble(),
  );
}

class CoverAsset {
  final String sourceFileId, fileName, mimeType, sha256;
  final int byteSize;

  const CoverAsset({
    required this.sourceFileId,
    required this.fileName,
    required this.mimeType,
    required this.sha256,
    required this.byteSize,
  });

  factory CoverAsset.fromJson(Map<String,dynamic> j)=>CoverAsset(
    sourceFileId:j['sourceFileId'] as String,
    fileName:j['fileName'] as String,
    mimeType:j['mimeType'] as String,
    sha256:j['sha256'] as String,
    byteSize:(j['byteSize'] as num).toInt(),
  );
}

abstract final class ContentType {
  static const book='book';
  static const comic='hq';
  static const manga='manga';
  static const graphicNovel='graphic_novel';
  static const magazine='magazine';
  static const values={book,comic,manga,graphicNovel,magazine};
}

class LibrarySection {
  static const classics='Grandes Clássicos';
  static const recommendations='Recomendações';
  static const bestWritten='Melhores escritos';
  static const essentials='Essenciais';
  static const recent='Adicionados recentemente';

  static String normalize(String raw){
    final x=raw.trim().toLowerCase();
    return switch(x){
      'grandes clássicos' || 'grandes classicos' || 'classicos' || 'clássicos' => classics,
      'recomendações' || 'recomendacoes' || 'recomendados' => recommendations,
      'melhores escritos' || 'melhor escritos' || 'best written' => bestWritten,
      'essenciais' || 'essencial' => essentials,
      'adicionados recentemente' || 'recentes' || 'novidades' => recent,
      _ => raw.trim(),
    };
  }
}

class Work {
  final String id, title, type;
  final CoverAsset? cover;
  final List<String> sources;
  final List<Edition> editions;
  final List<String> sections;
  final List<String> tags;

  const Work({
    required this.id,
    required this.title,
    required this.type,
    this.cover,
    required this.sources,
    required this.editions,
    this.sections=const [],
    this.tags=const [],
  });

  factory Work.fromJson(Map<String,dynamic> j){
    final id=j['id'] as String;
    final rawSections=<String>{
      ...List<String>.from(j['sections']??const[]),
      ...List<String>.from(j['editorialSections']??const[]),
    };
    final sections=rawSections
        .map(LibrarySection.normalize)
        .where((x)=>x.isNotEmpty)
        .toSet()
        .toList(growable:false);
    return Work(
      id:id,
      title:(j['displayTitle']??j['canonicalTitle']) as String,
      type:j['type'],
      cover:j['cover'] is Map
          ? CoverAsset.fromJson(Map<String,dynamic>.from(j['cover'] as Map))
          : null,
      sources:List<String>.from(j['sourceFolderIds']??const[]),
      editions:(j['editions'] as List? ?? const[])
          .map((e)=>Edition.fromJson(id,Map<String,dynamic>.from(e)))
          .toList(growable:false),
      sections:sections,
      tags:List<String>.from(j['tags']??const[]),
    );
  }
}
