sealed class ReadingLocator { const ReadingLocator(); Map<String,dynamic> toJson(); }
class PageLocator extends ReadingLocator { final int page; final int? pageCount; const PageLocator(this.page,{this.pageCount}); @override Map<String,dynamic> toJson()=>{'kind':'page','page':page,if(pageCount!=null)'pageCount':pageCount}; }
class EpubLocator extends ReadingLocator {
  final String href;
  final String? cfi;
  /// Progress inside the current spine document; used for restore fallback.
  final double? progression;
  /// Progress across the whole publication. Never substitute chapter progression for this.
  final double? bookProgression;
  final int? spineIndex;
  final int? spineCount;
  const EpubLocator(
    this.href,{
    this.cfi,
    this.progression,
    this.bookProgression,
    this.spineIndex,
    this.spineCount,
  });
  @override Map<String,dynamic> toJson()=>{
    'kind':'epub',
    'href':href,
    if(cfi!=null)'cfi':cfi,
    if(progression!=null)'progression':progression,
    if(bookProgression!=null)'bookProgression':bookProgression,
    if(spineIndex!=null)'spineIndex':spineIndex,
    if(spineCount!=null)'spineCount':spineCount,
  };
}
