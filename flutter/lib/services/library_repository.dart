import 'dart:convert';
import '../data/database.dart';
import '../models/catalog.dart';

class ReadingEntry {
  final Work work;
  final Edition edition;
  final double percent;
  final int updatedAt;

  const ReadingEntry({
    required this.work,
    required this.edition,
    required this.percent,
    required this.updatedAt,
  });
}

class LibraryRepository {
  final LumeDb db;
  LibraryRepository(this.db);

  Future<List<Work>> listByType(String type) async {
    final rows = await db.listWorks(type: type);
    return rows.map(Work.fromJson).toList(growable: false);
  }

  Future<List<Work>> all() async {
    final rows=await db.listWorks();
    return rows.map(Work.fromJson).toList(growable:false);
  }

  Future<List<ReadingEntry>> recentReading(String profileId,{int limit=12}) async {
    final rows=await db.listRecentReading(profileId,limit:limit);
    return rows.map((row){
      final work=Work.fromJson(Map<String,dynamic>.from(row['work'] as Map));
      final edition=Edition.fromJson(work.id,Map<String,dynamic>.from(row['edition'] as Map));
      return ReadingEntry(
        work:work,
        edition:edition,
        percent:(row['percent'] as num).toDouble().clamp(0.0,1.0).toDouble(),
        updatedAt:(row['updated_at'] as num).toInt(),
      );
    }).toList(growable:false);
  }

  Future<Set<String>> favorites(String profileId) async {
    final raw=await db.getSetting('favorites:$profileId');
    if(raw==null || raw.isEmpty)return <String>{};
    try{
      final decoded=jsonDecode(raw);
      if(decoded is! List)return <String>{};
      return decoded.whereType<String>().where((id)=>id.isNotEmpty).toSet();
    }catch(_){
      return <String>{};
    }
  }

  Future<bool> setFavorite(String profileId,String workId,bool favorite) async {
    final ids=await favorites(profileId);
    if(favorite){ids.add(workId);}else{ids.remove(workId);}
    final ordered=ids.toList()..sort();
    await db.setSetting('favorites:$profileId',jsonEncode(ordered));
    return favorite;
  }

  Future<List<Work>> listByTypeAndSection(String type,String? section) async {
    final works=await listByType(type);
    if(section==null || section.isEmpty)return works;
    final normalized=LibrarySection.normalize(section);
    return works.where((w)=>w.sections.contains(normalized)).toList(growable:false);
  }

  Future<List<String>> sectionsForType(String type) async {
    final works=await listByType(type);
    final found=<String>{};
    for(final w in works){found.addAll(w.sections);}
    const priority=[
      LibrarySection.classics,
      LibrarySection.recommendations,
      LibrarySection.bestWritten,
      LibrarySection.essentials,
      LibrarySection.recent,
    ];
    final result=<String>[];
    for(final p in priority){if(found.remove(p))result.add(p);}
    result.addAll(found.toList()..sort());
    return result;
  }

  Future<List<Work>> books() => listByType('book');
  Future<List<Work>> comics() => listByType('hq');
  Future<List<Work>> manga() => listByType('manga');
  Future<List<Work>> magazines() => listByType('magazine');
}
