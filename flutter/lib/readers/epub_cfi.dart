/// EPUB CFI is treated as an opaque locator, but we reject malformed/control
/// input before persisting or interpolating it into the bridge.
String? normalizeEpubCfi(Object? value){
  if(value is! String) return null;
  final s=value.trim();
  if(s.isEmpty || s.length>4096) return null;
  if(!s.startsWith('epubcfi(') || !s.endsWith(')')) return null;
  for(final unit in s.codeUnits){
    if(unit<0x20 || unit==0x7f) return null;
  }
  var depth=0;
  for(final r in s.runes){
    if(r==0x28) depth++;
    if(r==0x29){ depth--; if(depth<0)return null; }
  }
  return depth==0?s:null;
}
