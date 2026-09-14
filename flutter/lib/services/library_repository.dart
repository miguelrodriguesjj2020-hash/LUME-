import '../data/database.dart';
import '../models/catalog.dart';

class LibraryRepository {
  final LumeDb db;
  LibraryRepository(this.db);

  Future<List<Work>> listByType(String type) async {
    final rows = await db.listWorks(type: type);
    return rows.map(Work.fromJson).toList(growable: false);
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
}
