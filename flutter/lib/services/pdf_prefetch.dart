class PdfPrefetchTelemetry {
  final int hotBytes;
  final int budgetBytes;
  final int renderedPages;
  final int evictions;
  const PdfPrefetchTelemetry({required this.hotBytes,required this.budgetBytes,required this.renderedPages,required this.evictions});
  double get pressure=>budgetBytes<=0?1.0:(hotBytes/budgetBytes).clamp(0.0,2.0);
}

/// Chooses a small directional window and shrinks it under memory pressure.
/// This is deliberately renderer-agnostic until pdfx is compiled on Android.
List<int> pdfPrefetchWindow({
  required int page,
  required int pageCount,
  required int direction,
  int ahead=2,
  int behind=1,
  PdfPrefetchTelemetry? telemetry,
}) {
  final pressure=telemetry?.pressure??0.0;
  if(pressure>=0.90){ahead=0;behind=0;}
  else if(pressure>=0.70){ahead=1;behind=0;}
  final current=page-1;
  final out=<int>[];
  final forward=direction>=0;
  final first=forward?ahead:behind;
  final second=forward?behind:ahead;
  for(var d=1;d<=first;d++){
    final i=current+(forward?d:-d);
    if(i>=0&&i<pageCount)out.add(i+1);
  }
  for(var d=1;d<=second;d++){
    final i=current+(forward?-d:d);
    if(i>=0&&i<pageCount)out.add(i+1);
  }
  return out;
}

class PdfRenderBudget {
  final int maxBytes;
  int _hotBytes=0;
  int _renderedPages=0;
  int _evictions=0;
  PdfRenderBudget({this.maxBytes=24*1024*1024});
  bool canAdmit(int bytes)=>bytes>0 && bytes<=maxBytes && _hotBytes+bytes<=maxBytes;
  void admitted(int bytes){_hotBytes+=bytes;_renderedPages++;}
  void evicted(int bytes){_hotBytes=(_hotBytes-bytes).clamp(0,maxBytes);_evictions++;}
  PdfPrefetchTelemetry snapshot()=>PdfPrefetchTelemetry(hotBytes:_hotBytes,budgetBytes:maxBytes,renderedPages:_renderedPages,evictions:_evictions);
}
