import 'dart:convert';
import '../data/database.dart';

class CatalogDiagnosticIssue {
  final String severity;
  final String code;
  final String message;
  final Map<String,dynamic> context;
  const CatalogDiagnosticIssue(this.severity,this.code,this.message,[this.context=const {}]);
  Map<String,dynamic> toJson()=>{'severity':severity,'code':code,'message':message,'context':context};
}

class CatalogDiagnostics {
  final LumeDb db;
  CatalogDiagnostics(this.db);

  Future<List<CatalogDiagnosticIssue>> run() async {
    final d=await db.db;
    final issues=<CatalogDiagnosticIssue>[];
    final rows=await d.rawQuery('SELECT w.id AS work_id,w.title,w.type,e.id AS edition_id,e.json FROM works w LEFT JOIN editions e ON e.work_id=w.id ORDER BY w.title');
    final titleOwners=<String,List<String>>{};
    final sourceOwners=<String,List<String>>{};
    final editionCount=<String,int>{};
    for(final row in rows){
      final wid=row['work_id'] as String;
      final normalized=_norm(row['title']?.toString()??'');
      titleOwners.putIfAbsent(normalized,()=>[]).add(wid);
      if(row['edition_id']!=null){
        editionCount[wid]=(editionCount[wid]??0)+1;
        final raw=row['json'];
        if(raw is String){
          final e=Map<String,dynamic>.from(jsonDecode(raw));
          final sid=e['sourceFileId']?.toString();
          if(sid!=null && sid.isNotEmpty) sourceOwners.putIfAbsent(sid,()=>[]).add(row['edition_id'] as String);
        }
      }
    }
    for(final entry in titleOwners.entries){
      final ids=entry.value.toSet().toList();
      if(entry.key.isNotEmpty && ids.length>1){
        issues.add(CatalogDiagnosticIssue('warning','duplicate_normalized_title','Multiple works normalize to the same title',{'normalizedTitle':entry.key,'workIds':ids}));
      }
    }
    for(final entry in sourceOwners.entries){
      final ids=entry.value.toSet().toList();
      if(ids.length>1){
        issues.add(CatalogDiagnosticIssue('error','source_file_reused','A source file is referenced by multiple editions',{'sourceFileId':entry.key,'editionIds':ids}));
      }
    }
    for(final wid in titleOwners.values.expand((x)=>x).toSet()){
      if((editionCount[wid]??0)==0) issues.add(CatalogDiagnosticIssue('warning','work_without_editions','Work has no catalogued editions',{'workId':wid}));
    }
    return issues;
  }

  String toJsonReport(List<CatalogDiagnosticIssue> issues)=>const JsonEncoder.withIndent('  ').convert({
    'generatedAt':DateTime.now().toUtc().toIso8601String(),
    'issueCount':issues.length,
    'issues':issues.map((x)=>x.toJson()).toList(),
  });

  String toCsvReport(List<CatalogDiagnosticIssue> issues){
    String q(Object? v){final s=v?.toString()??'';return '"${s.replaceAll('"','""')}"';}
    final out=<String>['severity,code,message,context'];
    for(final x in issues){out.add([q(x.severity),q(x.code),q(x.message),q(jsonEncode(x.context))].join(','));}
    return out.join('\n');
  }

  static String _norm(String s)=>s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+',unicode:true),' ').trim().replaceAll(RegExp(r'\s+'),' ');
}
