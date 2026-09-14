class MediaDescriptor {
  final String editionId;
  final Uri url;
  final int? byteSize;
  final String? etag;
  final String? sha256;
  final String? revision;
  final Map<String,String> headers;
  const MediaDescriptor({required this.editionId,required this.url,this.byteSize,this.etag,this.sha256,this.revision,this.headers=const{}});
  factory MediaDescriptor.fromJson(Map<String,dynamic> j)=>MediaDescriptor(
    editionId:(j['editionId']??'') as String,
    url:Uri.parse(j['url'] as String),
    byteSize:(j['byteSize'] as num?)?.toInt(),etag:j['etag'] as String?,sha256:j['sha256'] as String?,revision:j['revision']?.toString(),
    headers:Map<String,String>.from((j['headers'] as Map?)?.map((k,v)=>MapEntry(k.toString(),v.toString()))??const{}),
  );
  String get fingerprint=>[revision,etag,sha256,byteSize].where((x)=>x!=null&&'$x'.isNotEmpty).join('|');
  String get sourceTag=>fingerprint;
}
