import '../models/progress.dart'; abstract interface class ReaderAdapter {Future<void> open(String localPath,ReadingLocator? locator);Future<ReadingLocator?> currentLocator();Future<void> close();}
