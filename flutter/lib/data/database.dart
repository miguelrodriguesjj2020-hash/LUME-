import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class CatalogIntegrityException implements Exception {
  final String message;
  const CatalogIntegrityException(this.message);
  @override String toString()=>'CatalogIntegrityException: $message';
}

void _validateCatalogManifest(Map<String,dynamic> m){
  final revision=m['revision'];
  if(revision is! int || revision<0) throw const CatalogIntegrityException('invalid revision');
  if(m['works'] is! List) throw const CatalogIntegrityException('works must be an array');
  final workIds=<String>{};
  final editionIds=<String>{};
  final tombstones=<String>{};
  final works=m['works'] as List? ?? const [];
  for(final raw in works){
    final w=Map<String,dynamic>.from(raw as Map);
    final wid=w['id'] as String?;
    if(wid==null || wid.trim().isEmpty) throw const CatalogIntegrityException('work id missing');
    if(!workIds.add(wid)) throw CatalogIntegrityException('duplicate work id: $wid');
    final type=w['type'] as String?;
    if(!const {'book','hq','manga','graphic_novel','magazine'}.contains(type)) throw CatalogIntegrityException('invalid work type for $wid: $type');
    final title=(w['displayTitle']??w['canonicalTitle']) as String?;
    if(title==null || title.trim().isEmpty) throw CatalogIntegrityException('work title missing for $wid');
    final cover=w['cover'];
    if(cover is! Map) throw CatalogIntegrityException('cover missing for $wid');
    final c=Map<String,dynamic>.from(cover);
    if(c['sourceFileId'] is! String || (c['sourceFileId'] as String).trim().isEmpty) throw CatalogIntegrityException('cover sourceFileId missing for $wid');
    if(c['fileName'] is! String || (c['fileName'] as String).trim().isEmpty) throw CatalogIntegrityException('cover fileName missing for $wid');
    if(!const {'image/jpeg','image/png','image/webp'}.contains(c['mimeType'])) throw CatalogIntegrityException('invalid cover mimeType for $wid: ${c['mimeType']}');
    if(c['byteSize'] is! int || (c['byteSize'] as int)<1) throw CatalogIntegrityException('invalid cover byteSize for $wid');
    if(c['sha256'] is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(c['sha256'] as String)) throw CatalogIntegrityException('invalid cover sha256 for $wid');
    if(w['editions'] is! List) throw CatalogIntegrityException('editions must be an array for $wid');
    for(final key in const ['sections','editorialSections','tags']){
      final value=w[key];
      if(value!=null && (value is! List || value.any((x)=>x is! String || x.trim().isEmpty))){
        throw CatalogIntegrityException('$key must be a non-empty string array for $wid');
      }
    }
    for(final er in (w['editions'] as List)){
      final e=Map<String,dynamic>.from(er as Map);
      final eid=e['id'] as String?;
      if(eid==null || eid.trim().isEmpty) throw CatalogIntegrityException('edition id missing in $wid');
      if(!editionIds.add(eid)) throw CatalogIntegrityException('duplicate edition id: $eid');
      final fmt=e['format'] as String?;
      if(!const {'pdf','epub','cbz'}.contains(fmt)) throw CatalogIntegrityException('invalid edition format for $eid: $fmt');
      final sourceFileId=e['sourceFileId'] as String?;
      final fileName=e['fileName'] as String?;
      if(sourceFileId==null || sourceFileId.trim().isEmpty) throw CatalogIntegrityException('sourceFileId missing for $eid');
      if(fileName==null || fileName.trim().isEmpty) throw CatalogIntegrityException('fileName missing for $eid');
    }
  }
  for(final raw in (m['tombstones'] as List? ?? const [])){
    final t=Map<String,dynamic>.from(raw as Map);
    final id=t['id'] as String?; final kind=t['kind'] as String?;
    if(id==null || id.isEmpty || !const {'work','edition'}.contains(kind)) throw const CatalogIntegrityException('invalid tombstone');
    final key='$kind:$id';
    if(!tombstones.add(key)) throw CatalogIntegrityException('duplicate tombstone: $key');
    if(kind=='work' && workIds.contains(id)) throw CatalogIntegrityException('work both present and tombstoned: $id');
    if(kind=='edition' && editionIds.contains(id)) throw CatalogIntegrityException('edition both present and tombstoned: $id');
  }
}

class LumeDb {
  Database? _db;

  Future<Database> get db async => _db ??= await openDatabase(
        join(await getDatabasesPath(), 'lume.db'),
        version: 11,
        onCreate: (d, v) async {
          await _create(d);
        },
        onUpgrade: (d, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await d.execute('CREATE INDEX IF NOT EXISTS idx_editions_work ON editions(work_id)');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at)');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_progress_updated ON progress(updated_at)');
          }
          if (oldVersion < 3) {
            await d.execute('ALTER TABLE outbox ADD COLUMN scope_key TEXT');
            await d.execute('ALTER TABLE offline_assets ADD COLUMN source_tag TEXT');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_outbox_scope ON outbox(kind,scope_key)');
          }
          if (oldVersion < 4) {
            await d.execute('ALTER TABLE offline_assets ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE offline_assets ADD COLUMN last_accessed_at INTEGER');
            await d.execute('ALTER TABLE offline_assets ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE offline_assets ADD COLUMN last_error TEXT');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_offline_lru ON offline_assets(state,pinned,last_accessed_at)');
          }
          if (oldVersion < 5) {
            await d.execute('CREATE TABLE IF NOT EXISTS download_jobs(edition_id TEXT PRIMARY KEY,state TEXT NOT NULL,request_json TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_download_jobs_state ON download_jobs(state,updated_at)');
          }
          if (oldVersion < 6) {
            await d.execute('CREATE TABLE IF NOT EXISTS media_revalidation(edition_id TEXT PRIMARY KEY,remote_source_tag TEXT,checked_at INTEGER NOT NULL,needs_update INTEGER NOT NULL DEFAULT 0,last_error TEXT)');
          }
          if (oldVersion < 7) {
            await d.execute('CREATE TABLE IF NOT EXISTS media_replacements(edition_id TEXT PRIMARY KEY,state TEXT NOT NULL,temp_path TEXT NOT NULL,expected_bytes INTEGER,received_bytes INTEGER NOT NULL DEFAULT 0,etag TEXT,sha256 TEXT,source_tag TEXT,updated_at INTEGER NOT NULL,last_error TEXT)');
            await d.execute('CREATE TABLE IF NOT EXISTS sync_retry(profile_id TEXT PRIMARY KEY,attempt INTEGER NOT NULL DEFAULT 0,next_retry_at INTEGER,last_error TEXT,updated_at INTEGER NOT NULL)');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_sync_retry_next ON sync_retry(next_retry_at)');
          }
          if (oldVersion < 8) {
            await d.execute('ALTER TABLE media_replacements ADD COLUMN staged_path TEXT');
            await d.execute('ALTER TABLE media_replacements ADD COLUMN backup_path TEXT');
            await d.execute("ALTER TABLE media_replacements ADD COLUMN phase TEXT NOT NULL DEFAULT 'downloading'");
            await d.execute("CREATE TABLE IF NOT EXISTS sync_schedule(profile_id TEXT PRIMARY KEY,mode TEXT NOT NULL DEFAULT 'foreground',last_attempt_at INTEGER,last_success_at INTEGER,deferred_until INTEGER,last_error TEXT,updated_at INTEGER NOT NULL)");
            await d.execute('CREATE INDEX IF NOT EXISTS idx_sync_schedule_deferred ON sync_schedule(deferred_until)');
          }
          if (oldVersion < 9) {
            await d.execute("CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY,v TEXT NOT NULL,updated_at INTEGER NOT NULL)");
          }
          if (oldVersion < 10) {
            await d.execute("CREATE TABLE IF NOT EXISTS retired_editions(edition_id TEXT PRIMARY KEY,json TEXT NOT NULL,retired_at INTEGER NOT NULL)");
            await d.execute('CREATE INDEX IF NOT EXISTS idx_retired_editions_at ON retired_editions(retired_at)');
          }
          if (oldVersion < 11) {
            await d.execute('ALTER TABLE outbox ADD COLUMN profile_id TEXT');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_outbox_profile_created ON outbox(profile_id,created_at)');
            await d.execute("CREATE TABLE IF NOT EXISTS outbox_dead_letter(op_id TEXT PRIMARY KEY,profile_id TEXT,kind TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL,quarantined_at INTEGER NOT NULL,reason TEXT NOT NULL)");
          }
        },
      );

  static Future<void> _create(DatabaseExecutor d) async {
    await d.execute('CREATE TABLE meta(k TEXT PRIMARY KEY,v TEXT NOT NULL)');
    await d.execute('CREATE TABLE works(id TEXT PRIMARY KEY,title TEXT NOT NULL,type TEXT NOT NULL,json TEXT NOT NULL)');
    await d.execute('CREATE TABLE editions(id TEXT PRIMARY KEY,work_id TEXT NOT NULL,json TEXT NOT NULL)');
    await d.execute('CREATE TABLE progress(profile_id TEXT NOT NULL,edition_id TEXT NOT NULL,locator TEXT NOT NULL,percent REAL NOT NULL,updated_at INTEGER NOT NULL,completed INTEGER NOT NULL DEFAULT 0,device_id TEXT,PRIMARY KEY(profile_id,edition_id))');
    await d.execute('CREATE TABLE outbox(op_id TEXT PRIMARY KEY,kind TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL,scope_key TEXT,profile_id TEXT)');
    await d.execute('CREATE TABLE offline_assets(edition_id TEXT PRIMARY KEY,state TEXT NOT NULL,local_path TEXT,temp_path TEXT,expected_bytes INTEGER,received_bytes INTEGER NOT NULL DEFAULT 0,etag TEXT,sha256 TEXT,updated_at INTEGER NOT NULL,source_tag TEXT,pinned INTEGER NOT NULL DEFAULT 0,last_accessed_at INTEGER,retry_count INTEGER NOT NULL DEFAULT 0,last_error TEXT)');
    await d.execute('CREATE INDEX idx_editions_work ON editions(work_id)');
    await d.execute('CREATE INDEX idx_outbox_created ON outbox(created_at)');
    await d.execute('CREATE INDEX idx_progress_updated ON progress(updated_at)');
    await d.execute('CREATE INDEX idx_outbox_scope ON outbox(kind,scope_key)');
    await d.execute('CREATE INDEX idx_offline_lru ON offline_assets(state,pinned,last_accessed_at)');
    await d.execute('CREATE TABLE download_jobs(edition_id TEXT PRIMARY KEY,state TEXT NOT NULL,request_json TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)');
    await d.execute('CREATE INDEX idx_download_jobs_state ON download_jobs(state,updated_at)');
    await d.execute('CREATE TABLE media_revalidation(edition_id TEXT PRIMARY KEY,remote_source_tag TEXT,checked_at INTEGER NOT NULL,needs_update INTEGER NOT NULL DEFAULT 0,last_error TEXT)');
    await d.execute("CREATE TABLE media_replacements(edition_id TEXT PRIMARY KEY,state TEXT NOT NULL,temp_path TEXT NOT NULL,expected_bytes INTEGER,received_bytes INTEGER NOT NULL DEFAULT 0,etag TEXT,sha256 TEXT,source_tag TEXT,updated_at INTEGER NOT NULL,last_error TEXT,staged_path TEXT,backup_path TEXT,phase TEXT NOT NULL DEFAULT 'downloading')");
    await d.execute('CREATE TABLE sync_retry(profile_id TEXT PRIMARY KEY,attempt INTEGER NOT NULL DEFAULT 0,next_retry_at INTEGER,last_error TEXT,updated_at INTEGER NOT NULL)');
    await d.execute('CREATE INDEX idx_sync_retry_next ON sync_retry(next_retry_at)');
    await d.execute("CREATE TABLE sync_schedule(profile_id TEXT PRIMARY KEY,mode TEXT NOT NULL DEFAULT 'foreground',last_attempt_at INTEGER,last_success_at INTEGER,deferred_until INTEGER,last_error TEXT,updated_at INTEGER NOT NULL)");
    await d.execute('CREATE INDEX idx_sync_schedule_deferred ON sync_schedule(deferred_until)');
    await d.execute("CREATE TABLE settings(k TEXT PRIMARY KEY,v TEXT NOT NULL,updated_at INTEGER NOT NULL)");
    await d.execute("CREATE TABLE retired_editions(edition_id TEXT PRIMARY KEY,json TEXT NOT NULL,retired_at INTEGER NOT NULL)");
    await d.execute('CREATE INDEX idx_retired_editions_at ON retired_editions(retired_at)');
    await d.execute('CREATE INDEX idx_outbox_profile_created ON outbox(profile_id,created_at)');
    await d.execute("CREATE TABLE outbox_dead_letter(op_id TEXT PRIMARY KEY,profile_id TEXT,kind TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL,quarantined_at INTEGER NOT NULL,reason TEXT NOT NULL)");
  }

  Future<String> getOrCreateDeviceId() async {
    final d = await db;
    final rows = await d.query('meta', columns: ['v'], where: 'k=?', whereArgs: ['device_id'], limit: 1);
    if (rows.isNotEmpty) return rows.first['v'] as String;
    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'android-$now';
    await d.insert('meta', {'k': 'device_id', 'v': id}, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<int> getRevision() async {
    final d = await db;
    final rows = await d.query('meta', columns: ['v'], where: 'k=?', whereArgs: ['revision'], limit: 1);
    return rows.isEmpty ? 0 : int.tryParse(rows.first['v'] as String) ?? 0;
  }

  Future<String> getSyncCursor(String profileId) async {
    final d = await db;
    final key = 'sync_cursor:$profileId';
    final rows = await d.query('meta', columns: ['v'], where: 'k=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? '0' : rows.first['v'] as String;
  }

  Future<void> setSyncCursor(String profileId, String cursor) async {
    final d = await db;
    await d.insert('meta', {'k': 'sync_cursor:$profileId', 'v': cursor}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _archiveEditionIfNeededTx(DatabaseExecutor t,String editionId) async {
    final editionRows=await t.query('editions',columns:['json'],where:'id=?',whereArgs:[editionId],limit:1);
    if(editionRows.isEmpty)return;
    final assets=await t.query('offline_assets',columns:['edition_id'],where:'edition_id=?',whereArgs:[editionId],limit:1);
    final progress=await t.query('progress',columns:['edition_id'],where:'edition_id=?',whereArgs:[editionId],limit:1);
    if(assets.isEmpty && progress.isEmpty)return;
    await t.insert('retired_editions',{
      'edition_id':editionId,
      'json':editionRows.first['json'],
      'retired_at':DateTime.now().millisecondsSinceEpoch,
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  static Future<void> _archiveAllAtRiskEditionsTx(DatabaseExecutor t) async {
    final rows=await t.rawQuery("""
      SELECT DISTINCT e.id
      FROM editions e
      LEFT JOIN offline_assets a ON a.edition_id=e.id
      LEFT JOIN progress p ON p.edition_id=e.id
      WHERE a.edition_id IS NOT NULL OR p.edition_id IS NOT NULL
    """);
    for(final row in rows){
      await _archiveEditionIfNeededTx(t,row['id'] as String);
    }
  }

  Future<void> applyCatalog(Map<String, dynamic> m) async {
    _validateCatalogManifest(m);
    final incomingRevision=(m['revision'] as num?)?.toInt() ?? 0;
    final currentRevision=await getRevision();
    if(incomingRevision<currentRevision) throw CatalogIntegrityException('catalog revision regression: $incomingRevision < $currentRevision');
    final d = await db;
    await d.transaction((t) async {
      final full = m['full'] == true;
      if (full) {
        await _archiveAllAtRiskEditionsTx(t);
        await t.delete('editions');
        await t.delete('works');
      }
      for (final raw in (m['works'] as List? ?? const [])) {
        final w = Map<String, dynamic>.from(raw);
        await t.insert('works', {
          'id': w['id'],
          'title': w['displayTitle'] ?? w['canonicalTitle'],
          'type': w['type'],
          'json': jsonEncode(w),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final incomingEditionIds = <String>{};
        for (final er in (w['editions'] as List? ?? const [])) {
          final e = Map<String, dynamic>.from(er);
          incomingEditionIds.add(e['id'] as String);
          await t.insert('editions', {
            'id': e['id'],
            'work_id': w['id'],
            'json': jsonEncode(e),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await t.delete('retired_editions',where:'edition_id=?',whereArgs:[e['id']]);
        }
        // A work payload is authoritative for its edition membership. This prevents
        // removed/renamed volumes from surviving forever after an incremental update.
        final existing = await t.query('editions', columns: ['id'], where: 'work_id=?', whereArgs: [w['id']]);
        for (final row in existing) {
          final id = row['id'] as String;
          if (!incomingEditionIds.contains(id)) {
            await _archiveEditionIfNeededTx(t,id);
            await t.delete('editions', where: 'id=?', whereArgs: [id]);
          }
        }
      }
      for (final tr in (m['tombstones'] as List? ?? const [])) {
        final x = Map<String, dynamic>.from(tr);
        if (x['kind'] == 'work') {
          final doomed=await t.query('editions',columns:['id'],where:'work_id=?',whereArgs:[x['id']]);
          for(final row in doomed){await _archiveEditionIfNeededTx(t,row['id'] as String);}
          await t.delete('editions', where: 'work_id=?', whereArgs: [x['id']]);
          await t.delete('works', where: 'id=?', whereArgs: [x['id']]);
        } else if (x['kind'] == 'edition') {
          await _archiveEditionIfNeededTx(t,x['id'] as String);
          await t.delete('editions', where: 'id=?', whereArgs: [x['id']]);
        }
      }
      await t.insert('meta', {'k': 'revision', 'v': '${m['revision'] ?? 0}'}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, dynamic>>> listWorks({String? type}) async {
    final d = await db;
    final rows = await d.query('works', where: type == null ? null : 'type=?', whereArgs: type == null ? null : [type], orderBy: 'title COLLATE NOCASE');
    return rows.map((r) => Map<String, dynamic>.from(jsonDecode(r['json'] as String))).toList();
  }

  Future<Map<String, dynamic>?> editionJson(String editionId) async {
    final d = await db;
    final rows = await d.query('editions', columns: ['json'], where: 'id=?', whereArgs: [editionId], limit: 1);
    if (rows.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(rows.first['json'] as String));
    final retired=await d.query('retired_editions',columns:['json'],where:'edition_id=?',whereArgs:[editionId],limit:1);
    if(retired.isEmpty)return null;
    return Map<String,dynamic>.from(jsonDecode(retired.first['json'] as String));
  }

  Future<Map<String, dynamic>?> getProgress(String profileId, String editionId) async {
    final d = await db;
    final rows = await d.query('progress', where: 'profile_id=? AND edition_id=?', whereArgs: [profileId, editionId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'profileId': profileId,
      'editionId': editionId,
      'locator': jsonDecode(r['locator'] as String),
      'percent': (r['percent'] as num).toDouble(),
      'clientUpdatedAt': r['updated_at'],
      'completed': (r['completed'] as int) == 1,
      'deviceId': r['device_id'],
    };
  }

  Future<void> upsertProgress(Map<String, dynamic> p, {bool enqueue = false}) async {
    final d = await db;
    await d.transaction((t) async {
      final accepted=await _upsertProgressTx(t, p);
      if (enqueue && accepted) {
        final opId = p['opId'] as String?;
        if (opId == null || opId.isEmpty) throw ArgumentError('opId required when enqueue=true');
        final scopeKey = '${p['profileId']}:${p['editionId']}';
        // Progress is last-write-wins. Keep only the newest unsent operation for
        // a profile+edition instead of flooding the outbox while pages turn.
        await t.delete('outbox', where: 'kind=? AND scope_key=?', whereArgs: ['progress', scopeKey]);
        await t.insert('outbox', {
          'op_id': opId,
          'kind': 'progress',
          'scope_key': scopeKey,
          'profile_id': p['profileId'],
          'payload': jsonEncode(p),
          'created_at': p['clientUpdatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<bool> _upsertProgressTx(DatabaseExecutor t, Map<String, dynamic> p) async {
    final profileId = p['profileId'] as String;
    final editionId = p['editionId'] as String;
    final incomingCompleted = p['completed'] == true;
    final existing = await t.query('progress', where: 'profile_id=? AND edition_id=?', whereArgs: [profileId, editionId], limit: 1);
    if (existing.isNotEmpty) {
      final old = existing.first;
      final oldCompleted = (old['completed'] as int) == 1;
      final oldUpdated = old['updated_at'] as int;
      final newUpdated = (p['clientUpdatedAt'] as num).toInt();
      if (oldCompleted && !incomingCompleted) return false;
      if (newUpdated < oldUpdated && !(incomingCompleted && !oldCompleted)) return false;
    }
    await t.insert('progress', {
      'profile_id': profileId,
      'edition_id': editionId,
      'locator': jsonEncode(p['locator']),
      'percent': ((p['percent'] ?? 0) as num).toDouble().clamp(0, 1),
      'updated_at': (p['clientUpdatedAt'] as num).toInt(),
      'completed': incomingCompleted ? 1 : 0,
      'device_id': p['deviceId'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> repairLegacyOutboxProfiles() async {
    final d=await db;
    final rows=await d.query('outbox',where:'profile_id IS NULL');
    await d.transaction((t) async {
      for(final r in rows){
        try{
          final payload=Map<String,dynamic>.from(jsonDecode(r['payload'] as String));
          final profileId=payload['profileId'] as String?;
          if(profileId==null || profileId.isEmpty)throw const FormatException('profileId missing');
          await t.update('outbox',{'profile_id':profileId},where:'op_id=?',whereArgs:[r['op_id']]);
        }catch(e){
          await _quarantineOutboxRowTx(t,r,'legacy repair: $e');
        }
      }
    });
  }

  static Future<void> _quarantineOutboxRowTx(DatabaseExecutor t,Map<String,Object?> r,String reason) async {
    await t.insert('outbox_dead_letter',{
      'op_id':r['op_id'],'profile_id':r['profile_id'],'kind':r['kind'],
      'payload':r['payload'],'created_at':r['created_at'],
      'quarantined_at':DateTime.now().millisecondsSinceEpoch,'reason':reason,
    },conflictAlgorithm:ConflictAlgorithm.replace);
    await t.delete('outbox',where:'op_id=?',whereArgs:[r['op_id']]);
  }

  Future<List<Map<String, dynamic>>> loadOutbox(String profileId,{int limit = 50}) async {
    final d = await db;
    final rows = await d.query('outbox', where:'profile_id=?', whereArgs:[profileId], orderBy: 'created_at ASC', limit: limit);
    final valid=<Map<String,dynamic>>[];
    await d.transaction((t) async {
      for(final r in rows){
        try{
          final payload=Map<String,dynamic>.from(jsonDecode(r['payload'] as String));
          if(payload['profileId']!=profileId)throw const FormatException('profile mismatch');
          payload['opId'] ??= r['op_id'];
          payload['kind'] ??= r['kind'];
          valid.add(payload);
        }catch(e){
          await _quarantineOutboxRowTx(t,Map<String,Object?>.from(r),'decode: $e');
        }
      }
    });
    return valid;
  }

  Future<int> deadLetterOutboxCount() async {
    final d=await db;
    final rows=await d.rawQuery('SELECT COUNT(*) AS n FROM outbox_dead_letter');
    return (rows.first['n'] as num?)?.toInt()??0;
  }

  Future<void> applySyncBatch(String profileId,{
    required Iterable<String> ackOpIds,
    required List<dynamic> events,
    required List<dynamic> rejected,
    required String previousCursor,
    required String nextCursor,
  }) async {
    final prev=int.tryParse(previousCursor);
    final next=int.tryParse(nextCursor);
    if(prev==null || next==null || next<prev)throw StateError('invalid sync cursor transition $previousCursor -> $nextCursor');
    final d=await db;
    await d.transaction((t) async {
      final ids=ackOpIds.toSet().toList(growable:false);
      if(ids.isNotEmpty){
        final marks=List.filled(ids.length,'?').join(',');
        await t.delete('outbox',where:'profile_id=? AND op_id IN ($marks)',whereArgs:[profileId,...ids]);
      }
      for(final raw in rejected){
        if(raw is! Map)continue;
        final r=Map<String,dynamic>.from(raw);
        final opId=r['opId'];
        if(opId is! String || opId.isEmpty)continue;
        final rows=await t.query('outbox',where:'profile_id=? AND op_id=?',whereArgs:[profileId,opId],limit:1);
        if(rows.isNotEmpty){
          await _quarantineOutboxRowTx(t,Map<String,Object?>.from(rows.first),'server rejected: ${r['reason'] ?? 'invalid operation'}');
        }
      }
      var lastSeq=prev;
      for(final raw in events){
        if(raw is! Map)throw const FormatException('sync event must be an object');
        final e=Map<String,dynamic>.from(raw);
        final seq=e['seq'];
        if(seq is! int || seq<=lastSeq || seq>next)throw FormatException('invalid sync event sequence: $seq');
        if(e['profile']!=profileId)throw const FormatException('sync event profile mismatch');
        if(e['payload'] is! Map || e['edition'] is! String || (e['edition'] as String).isEmpty)throw const FormatException('invalid sync event payload');
        final p=Map<String,dynamic>.from(e['payload'] as Map);
        p['profileId']=profileId;
        p['editionId']=e['edition'];
        await _upsertProgressTx(t,p);
        lastSeq=seq;
      }
      if(events.isEmpty && next!=prev)throw const FormatException('cursor advanced without events');
      if(events.isNotEmpty && lastSeq!=next)throw const FormatException('cursor does not match final event');
      await t.insert('meta',{'k':'sync_cursor:$profileId','v':'$next'},conflictAlgorithm:ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, dynamic>?> getOfflineAsset(String editionId) async {
    final d = await db;
    final rows = await d.query('offline_assets', where: 'edition_id=?', whereArgs: [editionId], limit: 1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> setOfflineAssetState(String editionId, String state) async {
    final d = await db;
    await d.update('offline_assets', {
      'state': state,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'edition_id=?', whereArgs: [editionId]);
  }

  Future<void> upsertOfflineAsset(Map<String, dynamic> a) async {
    final d = await db;
    await d.insert('offline_assets', {
      'edition_id': a['editionId'],
      'state': a['state'],
      'local_path': a['localPath'],
      'temp_path': a['tempPath'],
      'expected_bytes': a['expectedBytes'],
      'received_bytes': a['receivedBytes'] ?? 0,
      'etag': a['etag'],
      'sha256': a['sha256'],
      'source_tag': a['sourceTag'],
      'updated_at': a['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      'pinned': a['pinned'] == true ? 1 : (a['pinned'] is num ? a['pinned'] : 0),
      'last_accessed_at': a['lastAccessedAt'],
      'retry_count': a['retryCount'] ?? 0,
      'last_error': a['lastError'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> touchOfflineAsset(String editionId) async {
    final d = await db;
    await d.update('offline_assets', {'last_accessed_at': DateTime.now().millisecondsSinceEpoch}, where: 'edition_id=?', whereArgs: [editionId]);
  }

  Future<void> setOfflinePinned(String editionId, bool pinned) async {
    final d = await db;
    await d.update('offline_assets', {'pinned': pinned ? 1 : 0}, where: 'edition_id=?', whereArgs: [editionId]);
  }

  Future<List<Map<String, dynamic>>> evictionCandidates({int limit = 100}) async {
    final d = await db;
    final rows = await d.rawQuery("SELECT * FROM offline_assets WHERE state='ready' AND pinned=0 AND edition_id NOT IN (SELECT edition_id FROM media_replacements WHERE state IN ('downloading','verifying')) ORDER BY COALESCE(last_accessed_at,updated_at) ASC LIMIT ?",[limit]);
    return rows.map((r) => Map<String,dynamic>.from(r)).toList();
  }

  Future<void> deleteOfflineAsset(String editionId) async {
    final d = await db;
    await d.delete('offline_assets', where: 'edition_id=?', whereArgs: [editionId]);
  }

  Future<int> readyOfflineBytes() async {
    final d = await db;
    final rows = await d.rawQuery("SELECT COALESCE(SUM(COALESCE(expected_bytes,received_bytes,0)),0) AS total FROM offline_assets WHERE state='ready'");
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> reservedOfflineBytes() async {
    final d=await db;
    final rows=await d.rawQuery("SELECT (SELECT COALESCE(SUM(CASE WHEN COALESCE(expected_bytes,0)>received_bytes THEN expected_bytes-received_bytes ELSE 0 END),0) FROM offline_assets WHERE state IN ('queued','downloading','verifying','paused')) + (SELECT COALESCE(SUM(CASE WHEN COALESCE(expected_bytes,0)>received_bytes THEN expected_bytes-received_bytes ELSE 0 END),0) FROM media_replacements WHERE state IN ('downloading','verifying')) AS total");
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> upsertDownloadJob({required String editionId, required String state, required Map<String,dynamic> request}) async {
    final d=await db; final now=DateTime.now().millisecondsSinceEpoch;
    final old=await d.query('download_jobs',columns:['created_at'],where:'edition_id=?',whereArgs:[editionId],limit:1);
    await d.insert('download_jobs',{
      'edition_id':editionId,'state':state,'request_json':jsonEncode(request),
      'created_at':old.isEmpty?now:old.first['created_at'],'updated_at':now,
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<void> setDownloadJobState(String editionId,String state) async {
    final d=await db; await d.update('download_jobs',{'state':state,'updated_at':DateTime.now().millisecondsSinceEpoch},where:'edition_id=?',whereArgs:[editionId]);
  }

  Future<List<Map<String,dynamic>>> recoverableDownloadJobs() async {
    final d=await db;
    final rows=await d.query('download_jobs',where:"state IN ('queued','downloading','verifying','failed')",orderBy:'updated_at ASC');
    return rows.map((r)=>{...Map<String,dynamic>.from(r),'request':jsonDecode(r['request_json'] as String)}).toList();
  }

  Future<List<Map<String,dynamic>>> listDownloadJobs() async {
    final d=await db; final rows=await d.query('download_jobs',orderBy:'updated_at DESC');
    return rows.map((r)=>{...Map<String,dynamic>.from(r),'request':jsonDecode(r['request_json'] as String)}).toList();
  }

  Future<void> deleteDownloadJob(String editionId) async { final d=await db; await d.delete('download_jobs',where:'edition_id=?',whereArgs:[editionId]); }

  Future<void> normalizeInterruptedDownloads() async {
    final d=await db; final now=DateTime.now().millisecondsSinceEpoch;
    await d.transaction((t) async {
      await t.update('download_jobs',{'state':'queued','updated_at':now},where:"state IN ('downloading','verifying')");
      await t.update('offline_assets',{'state':'queued','updated_at':now},where:"state IN ('downloading','verifying')");
    });
  }

  Future<void> recordMediaRevalidation(String editionId,{String? remoteSourceTag,required bool needsUpdate,String? lastError}) async {
    final d=await db;
    await d.insert('media_revalidation',{
      'edition_id':editionId,'remote_source_tag':remoteSourceTag,
      'checked_at':DateTime.now().millisecondsSinceEpoch,
      'needs_update':needsUpdate?1:0,'last_error':lastError,
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<Map<String,dynamic>?> getMediaRevalidation(String editionId) async {
    final d=await db; final rows=await d.query('media_revalidation',where:'edition_id=?',whereArgs:[editionId],limit:1);
    return rows.isEmpty?null:Map<String,dynamic>.from(rows.first);
  }

  Future<List<Map<String,dynamic>>> recentlyAccessedReadyAssets({int limit=5}) async {
    final d=await db;
    final rows=await d.query('offline_assets',where:"state='ready'",orderBy:'COALESCE(last_accessed_at,updated_at) DESC',limit:limit);
    return rows.map((r)=>Map<String,dynamic>.from(r)).toList();
  }

  Future<void> upsertMediaReplacement(Map<String,dynamic> r) async {
    final d=await db;
    await d.insert('media_replacements',{
      'edition_id':r['editionId'],'state':r['state'],'temp_path':r['tempPath'],
      'expected_bytes':r['expectedBytes'],'received_bytes':r['receivedBytes']??0,
      'etag':r['etag'],'sha256':r['sha256'],'source_tag':r['sourceTag'],
      'updated_at':r['updatedAt']??DateTime.now().millisecondsSinceEpoch,'last_error':r['lastError'],
      'staged_path':r['stagedPath'],'backup_path':r['backupPath'],'phase':r['phase']??r['state']??'downloading',
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<Map<String,dynamic>?> getMediaReplacement(String editionId) async {
    final d=await db; final rows=await d.query('media_replacements',where:'edition_id=?',whereArgs:[editionId],limit:1);
    return rows.isEmpty?null:Map<String,dynamic>.from(rows.first);
  }

  Future<void> deleteMediaReplacement(String editionId) async {
    final d=await db; await d.delete('media_replacements',where:'edition_id=?',whereArgs:[editionId]);
  }

  Future<void> saveSyncRetry(String profileId,{required int attempt,required int? nextRetryAt,String? lastError}) async {
    final d=await db;
    await d.insert('sync_retry',{
      'profile_id':profileId,'attempt':attempt,'next_retry_at':nextRetryAt,
      'last_error':lastError,'updated_at':DateTime.now().millisecondsSinceEpoch,
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<Map<String,dynamic>?> getSyncRetry(String profileId) async {
    final d=await db; final rows=await d.query('sync_retry',where:'profile_id=?',whereArgs:[profileId],limit:1);
    return rows.isEmpty?null:Map<String,dynamic>.from(rows.first);
  }

  Future<void> clearSyncRetry(String profileId) async {
    final d=await db; await d.delete('sync_retry',where:'profile_id=?',whereArgs:[profileId]);
  }

  Future<List<Map<String,dynamic>>> listMediaReplacements() async {
    final d=await db; final rows=await d.query('media_replacements',orderBy:'updated_at ASC');
    return rows.map((r)=>Map<String,dynamic>.from(r)).toList();
  }

  Future<List<Map<String,dynamic>>> listPendingMediaUpdates() async {
    final d=await db;
    final rows=await d.rawQuery("SELECT r.edition_id,r.remote_source_tag,r.checked_at,r.last_error,e.json AS edition_json,m.state AS replacement_state,m.phase AS replacement_phase,m.received_bytes AS replacement_received_bytes,m.expected_bytes AS replacement_expected_bytes,m.last_error AS replacement_last_error FROM media_revalidation r LEFT JOIN editions e ON e.id=r.edition_id LEFT JOIN media_replacements m ON m.edition_id=r.edition_id WHERE r.needs_update=1 ORDER BY r.checked_at DESC");
    return rows.map((r)=>{
      ...Map<String,dynamic>.from(r),
      if(r['edition_json'] is String) 'edition':jsonDecode(r['edition_json'] as String),
    }).toList();
  }

  Future<void> saveSyncSchedule(String profileId,{required String mode,int? lastAttemptAt,int? lastSuccessAt,int? deferredUntil,String? lastError}) async {
    final d=await db; final previous=await getSyncSchedule(profileId); final now=DateTime.now().millisecondsSinceEpoch;
    await d.insert('sync_schedule',{
      'profile_id':profileId,'mode':mode,
      'last_attempt_at':lastAttemptAt??previous?['last_attempt_at'],
      'last_success_at':lastSuccessAt??previous?['last_success_at'],
      'deferred_until':deferredUntil,'last_error':lastError,'updated_at':now,
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<Map<String,dynamic>?> getSyncSchedule(String profileId) async {
    final d=await db; final rows=await d.query('sync_schedule',where:'profile_id=?',whereArgs:[profileId],limit:1);
    return rows.isEmpty?null:Map<String,dynamic>.from(rows.first);
  }

  Future<void> clearSyncScheduleDeferral(String profileId,{required String mode}) async {
    final now=DateTime.now().millisecondsSinceEpoch;
    await saveSyncSchedule(profileId,mode:mode,lastSuccessAt:now,deferredUntil:null,lastError:null);
  }

  Future<int> pruneUnreferencedRetiredEditions() async {
    final d=await db;
    return d.rawDelete("""
      DELETE FROM retired_editions
      WHERE edition_id NOT IN (SELECT edition_id FROM offline_assets)
        AND edition_id NOT IN (SELECT edition_id FROM progress)
    """);
  }

  Future<void> setSetting(String key,String value) async {
    final d=await db;
    await d.insert('settings',{'k':key,'v':value,'updated_at':DateTime.now().millisecondsSinceEpoch},conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final d=await db; final rows=await d.query('settings',columns:['v'],where:'k=?',whereArgs:[key],limit:1);
    return rows.isEmpty?null:rows.first['v'] as String;
  }


}
