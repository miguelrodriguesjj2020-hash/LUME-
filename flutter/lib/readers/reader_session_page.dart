import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../models/progress.dart';
import '../services/app_services.dart';
import '../services/media_open_coordinator.dart';
import 'reader_factory.dart';

class ReaderSessionPage extends StatefulWidget {
  final Edition edition;
  final AppServices services;
  const ReaderSessionPage({super.key, required this.edition, required this.services});

  @override
  State<ReaderSessionPage> createState() => _ReaderSessionPageState();
}

class _ReaderSessionPageState extends State<ReaderSessionPage> {
  late Future<OpenedMedia> opening;
  ReadingLocator? _lastSaved;

  @override
  void initState() {
    super.initState();
    if(widget.edition.format.toLowerCase()=='cbr'){
      opening=Future<OpenedMedia>.error(
        UnsupportedError('CBR/RAR ainda não possui cadeia de extração validada'),
      );
    }else{
      opening = widget.services.mediaOpen.open(
        edition: widget.edition,
        profileId: widget.services.profileId,
      );
    }
  }

  Future<void> _save(ReadingLocator locator) async {
    // Reader widgets may emit the same locator repeatedly during layout/visibility
    // changes. Avoid unnecessary SQLite/outbox writes before the DB coalescer.
    if (_lastSaved?.toJson().toString() == locator.toJson().toString()) return;
    _lastSaved = locator;
    await widget.services.progress().save(widget.edition.id, locator);
  }

  @override
  Widget build(BuildContext context) {
    if(widget.edition.format.toLowerCase()=='cbr'){
      return Scaffold(
        appBar:AppBar(title:Text(widget.edition.fileName)),
        body:const Center(child:Padding(
          padding:EdgeInsets.all(24),
          child:Text(
            'Este arquivo usa CBR/RAR. A LUME não fará download nem extração automática enquanto a cadeia RAR não estiver validada com segurança.',
            textAlign:TextAlign.center,
          ),
        )),
      );
    }
    return FutureBuilder<OpenedMedia>(
        future: opening,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.edition.fileName)),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, size: 44),
                    const SizedBox(height: 12),
                    Text('Não foi possível preparar esta edição.\n${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() {
                        opening = widget.services.mediaOpen.open(
                          edition: widget.edition,
                          profileId: widget.services.profileId,
                        );
                      }),
                      child: const Text('Tentar novamente'),
                    ),
                  ]),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final opened = snapshot.data!;
          return readerFor(
            edition: widget.edition,
            localPath: opened.localPath,
            preparedEpubEntry: opened.epubEntryPath ?? opened.epub?.spine.first,
            preparedEpubRoot: opened.epub?.root.path,
            preparedEpubSpine: opened.epub?.spine,
            epubFixedLayout: opened.epub?.fixedLayout ?? false,
            preparedCbzPages: opened.cbz?.pages,
            locator: opened.locator,
            onProgress: _save,
          );
        },
      );
  }
}
