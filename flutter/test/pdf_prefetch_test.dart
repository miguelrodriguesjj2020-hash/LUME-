import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/pdf_prefetch.dart';

void main(){
  test('directional prefetch is aggressive only with memory headroom',(){
    const low=PdfPrefetchTelemetry(hotBytes:2,budgetBytes:10,renderedPages:1,evictions:0);
    const mid=PdfPrefetchTelemetry(hotBytes:8,budgetBytes:10,renderedPages:4,evictions:1);
    const high=PdfPrefetchTelemetry(hotBytes:10,budgetBytes:10,renderedPages:5,evictions:2);
    expect(pdfPrefetchWindow(page:5,pageCount:20,direction:1,telemetry:low),[6,7,4]);
    expect(pdfPrefetchWindow(page:5,pageCount:20,direction:1,telemetry:mid),[6]);
    expect(pdfPrefetchWindow(page:5,pageCount:20,direction:1,telemetry:high),isEmpty);
  });

  test('render budget never admits beyond cap',(){
    final b=PdfRenderBudget(maxBytes:100);
    expect(b.canAdmit(60),isTrue); b.admitted(60);
    expect(b.canAdmit(50),isFalse);
    b.evicted(30); expect(b.canAdmit(50),isTrue);
  });
}
