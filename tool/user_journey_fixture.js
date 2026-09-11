const http=require('http');
const fs=require('fs');
const crypto=require('crypto');
const path=require('path');

const PORT=Number(process.env.PORT||18787);
const MEDIA=path.resolve(process.env.LUME_JOURNEY_MEDIA||'journey-media.cbz');
const TOKEN='journey-token';
const REVISION=901;
let progress=[];

function send(res,status,body,headers={}){
  res.writeHead(status,{'content-type':'application/json','cache-control':'no-store',...headers});
  res.end(body===undefined?'':JSON.stringify(body));
}
function body(req){return new Promise((resolve,reject)=>{let b='';req.on('data',c=>b+=c);req.on('end',()=>{try{resolve(JSON.parse(b||'{}'));}catch(e){reject(e);}});});}
function authed(req){return req.headers.authorization===`Bearer ${TOKEN}`;}
function catalog(){return {revision:REVISION,full:true,tombstones:[],works:[
  {id:'book-journey',type:'book',displayTitle:'Clássico da Jornada',sections:['Grandes Clássicos','Essenciais'],editions:[{id:'ed-book',format:'pdf',sourceFileId:'book-src',fileName:'classico.pdf',language:'pt-BR'}]},
  {id:'hq-journey',type:'hq',displayTitle:'HQ Jornada',sections:['Recomendações','Melhores escritos'],editions:[{id:'ed-cbz',format:'cbz',sourceFileId:'cbz-src',fileName:'hq-jornada.cbz',language:'pt-BR'}]},
  {id:'manga-journey',type:'manga',displayTitle:'Mangá Jornada',sections:['Adicionados recentemente'],editions:[{id:'ed-manga',format:'epub',sourceFileId:'manga-src',fileName:'manga.epub',language:'pt-BR'}]}
]};}
function mediaMeta(){const bytes=fs.readFileSync(MEDIA);return {bytes,size:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),etag:'"journey-v1"'};}

const server=http.createServer(async(req,res)=>{
  try{
    const u=new URL(req.url,'http://x');
    if(req.method==='GET'&&u.pathname==='/v1/health')return send(res,200,{ok:true,service:'lume',protocol:1});
    if(req.method==='GET'&&u.pathname==='/v1/ready')return send(res,200,{ok:true,service:'lume',protocol:1,durable:true,revision:REVISION,configOk:true});
    if(req.method==='POST'&&u.pathname==='/v1/auth/login'){
      const j=await body(req);
      if(j.username!=='aluno'||j.password!=='lume2026')return send(res,401,{error:'invalid_credentials'});
      return send(res,200,{token:TOKEN,profileId:'reader-01',role:'consumer',expiresAt:Date.now()+8*60*60*1000});
    }
    if(req.method==='GET'&&u.pathname==='/v1/bootstrap'){
      if(!authed(req))return send(res,401,{error:'unauthorized'});
      if(Number(u.searchParams.get('since')||0)===REVISION){res.writeHead(304,{'cache-control':'no-store'});return res.end();}
      return send(res,200,catalog());
    }
    if(req.method==='GET'&&u.pathname==='/v1/media/ed-cbz'){
      if(!authed(req))return send(res,401,{error:'unauthorized'});
      const m=mediaMeta();
      return send(res,200,{strategy:'signed',editionId:'ed-cbz',expiresAt:Date.now()+300000,token:'journey',byteSize:m.size,etag:m.etag,sha256:m.sha256,url:`http://10.0.2.2:${PORT}/media/journey.cbz`});
    }
    if(req.method==='POST'&&u.pathname==='/v1/profiles/reader-01/sync'){
      if(!authed(req))return send(res,401,{error:'unauthorized'});
      const j=await body(req);const ops=Array.isArray(j.ops)?j.ops:[];
      progress.push(...ops);
      return send(res,200,{cursor:String(progress.length),events:[],ack:ops.map(x=>x.opId).filter(Boolean),rejected:[]});
    }
    if(req.method==='GET'&&u.pathname==='/media/journey.cbz'){
      const m=mediaMeta();
      const range=req.headers.range;
      if(range){const hit=/^bytes=(\d+)-$/.exec(range);if(!hit)return send(res,416,{error:'bad_range'});const start=Number(hit[1]);const chunk=m.bytes.subarray(start);res.writeHead(206,{'content-type':'application/vnd.comicbook+zip','content-length':String(chunk.length),'content-range':`bytes ${start}-${m.size-1}/${m.size}`,'etag':m.etag});return res.end(chunk);}
      res.writeHead(200,{'content-type':'application/vnd.comicbook+zip','content-length':String(m.size),'etag':m.etag});return res.end(m.bytes);
    }
    return send(res,404,{error:'not_found'});
  }catch(e){return send(res,500,{error:String(e&&e.message||e)});}
});
server.listen(PORT,'0.0.0.0',()=>console.log(`journey fixture listening ${PORT}`));
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
