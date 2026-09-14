import '../models/progress.dart';
import 'epub_cfi.dart';

/// Installs the subset of EPUB Content CFI needed by LUME inside a single
/// spine document. The chapter href is persisted separately, so package/spine
/// indirection is intentionally not encoded in this bridge.
String cfiBridgeInstallScript() => r'''(()=>{
if(window.LUME&&window.LUME.__cfiVersion===1)return;
const esc=s=>String(s).replace(/([\^\[\]\(\),;=])/g,'^$1');
const stepFor=n=>{
  if(n.nodeType===1){const a=[...n.parentNode.children];return String((a.indexOf(n)+1)*2)+(n.id?'['+esc(n.id)+']':'');}
  if(n.nodeType===3){const before=[...n.parentNode.childNodes].slice(0,[...n.parentNode.childNodes].indexOf(n));const elements=before.filter(x=>x.nodeType===1).length;return String(elements*2+1);}
  return null;
};
const pathTo=n=>{const steps=[];let x=n;while(x&&x!==document.documentElement){const st=stepFor(x);if(st)steps.unshift(st);x=x.parentNode;}return 'epubcfi(/'+steps.join('/')+')';};
const unesc=s=>String(s||'').replace(/\^(.)/g,'$1');
const resolve=cfi=>{
  if(typeof cfi!=='string'||!cfi.startsWith('epubcfi(/')||!cfi.endsWith(')'))return null;
  const raw=cfi.slice(9,-1).split('/').filter(Boolean);let n=document.documentElement;
  for(const token of raw){const m=token.match(/^(\d+)(?:\[([^\]]*)\])?(?::(\d+))?$/);if(!m)return null;const k=Number(m[1]);
    if(k%2===0){const els=[...n.children];n=els[k/2-1];if(!n)return null;if(m[2]&&n.id&&n.id!==unesc(m[2])){const byId=document.getElementById(unesc(m[2]));if(byId)n=byId;}}
    else {const elementBefore=(k-1)/2;let seen=0,found=null;for(const child of n.childNodes){if(child.nodeType===1){seen++;continue;}if(child.nodeType===3&&seen===elementBefore){found=child;break;}}n=found;if(!n)return null;}
  }return n;
};
window.LUME={__cfiVersion:1,
 currentCfi(){let n=null;const sel=getSelection();if(sel&&sel.rangeCount)n=sel.getRangeAt(0).startContainer;if(!n){const e=document.elementFromPoint(innerWidth/2,Math.max(1,innerHeight/3));n=e||document.body;}return pathTo(n);},
 restoreCfi(cfi){const n=resolve(cfi);if(!n)return false;const e=n.nodeType===1?n:n.parentElement;if(!e)return false;e.scrollIntoView({block:'center'});return true;}
};})();''';

String restoreScript(EpubLocator l) {
  final cfi = normalizeEpubCfi(l.cfi);
  final p = (l.progression ?? 0).clamp(0, 1);
  return '''(()=>{const cfi=${cfi == null ? 'null' : _q(cfi)};const p=$p;if(cfi&&window.LUME?.restoreCfi){try{if(window.LUME.restoreCfi(cfi))return;}catch(e){}}const h=Math.max(0,document.documentElement.scrollHeight-innerHeight);scrollTo(0,h*p);})()''';
}

String progressCaptureScript(String href) => '''(()=>{if(window.__lumeProgressInstalled)return;window.__lumeProgressInstalled=true;let timer=null;const send=()=>{const h=Math.max(1,document.documentElement.scrollHeight-innerHeight);const p=Math.max(0,Math.min(1,scrollY/h));let cfi=null;try{if(window.LUME?.currentCfi)cfi=window.LUME.currentCfi();}catch(e){}LumeProgress.postMessage(JSON.stringify({href:${_q(href)},cfi:cfi,progression:p}));};addEventListener('scroll',()=>{clearTimeout(timer);timer=setTimeout(send,180)},{passive:true});addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')send()});send();})()''';

String _q(String s) => "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";
