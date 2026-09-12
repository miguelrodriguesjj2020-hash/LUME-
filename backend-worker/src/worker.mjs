import {D1Store} from './storage.mjs';
import {normalizeLocator} from './reader_position.mjs';
import {applyCatalogManifest} from './catalog_d1.mjs';
import {normalizeUsername,verifyPasswordVerifier,signSession,verifySession,hmacB64url,verifyHmacB64url} from './crypto.mjs';
import {proxyDriveMedia} from './drive.mjs';

const SESSION_MS=8*60*60*1000,MEDIA_TTL_SECONDS=300;
function json(data,status=200,headers={}){return new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff',...headers}})}
function nowIso(){return new Date().toISOString()}
function secretStrong(v){return typeof v==='string'&&v.length>=32}
function production(env){return String(env.LUME_ENV||'').toLowerCase()==='production'}
function safePath(v){try{return decodeURIComponent(v)}catch{return v}}

export function validateRuntimeConfig(env){
  const issues=[];if(!env.DB)issues.push('DB binding required');
  if(!secretStrong(env.AUTH_SECRET))issues.push('AUTH_SECRET must be at least 32 characters');
  if(!secretStrong(env.MEDIA_SIGNING_SECRET))issues.push('MEDIA_SIGNING_SECRET must be at least 32 characters');
  if(!secretStrong(env.PASSWORD_PEPPER))issues.push('PASSWORD_PEPPER must be at least 32 characters');
  let sa=null;try{sa=JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON||'')}catch{issues.push('GOOGLE_SERVICE_ACCOUNT_JSON invalid JSON')}
  if(!sa?.client_email||!sa?.private_key)issues.push('Google service account credentials incomplete');
  if(production(env)&&!env.LOGIN_RATE_LIMITER)issues.push('LOGIN_RATE_LIMITER binding required in production');
  return {ok:issues.length===0,production:production(env),issues};
}
export function resolveProgress(local,remote){if(!local)return remote;if(!remote)return local;if(local.completed&&!remote.completed)return local;if(remote.completed&&!local.completed)return remote;return remote.clientUpdatedAt>=local.clientUpdatedAt?remote:local}
async function authenticate(req,env){const m=/^Bearer\s+(.+)$/i.exec(req.headers.get('authorization')||'');return m?verifySession(m[1],env.AUTH_SECRET):null}
function canAccessProfile(auth,profile){return !!auth&&(auth.role==='admin'||auth.profileId===profile)}
async function rateLimitLogin(env,username){if(!env.LOGIN_RATE_LIMITER)return true;const {success}=await env.LOGIN_RATE_LIMITER.limit({key:`login:${username||'unknown'}`});return !!success}
async function putProgressD1(store,profileId,editionId,body){
  const cached=await store.getIdempotent(body.opId);if(cached)return cached;
  const incoming={...body,locator:normalizeLocator(body.locator),profileId,editionId,completed:!!body.completed,serverUpdatedAt:nowIso()};
  const chosen=resolveProgress(await store.getProgress(profileId,editionId),incoming);if(chosen===incoming)await store.saveProgress(chosen);await store.putIdempotent(body.opId,chosen);return chosen;
}
async function mediaSignature(env,editionId,exp,revision){return hmacB64url(env.MEDIA_SIGNING_SECRET,`${editionId}.${exp}.${revision??''}`)}
async function mediaDescriptor(req,env,edition){const exp=Math.floor(Date.now()/1000)+MEDIA_TTL_SECONDS;const sig=await mediaSignature(env,edition.id,exp,edition.source_revision);const u=new URL(req.url);u.pathname=`/v1/media/${encodeURIComponent(edition.id)}/file`;u.search='';u.searchParams.set('exp',String(exp));u.searchParams.set('sig',sig);return {editionId:edition.id,url:u.toString(),expiresAt:exp*1000,byteSize:edition.byte_size??null,sha256:edition.sha256??null,revision:edition.source_revision??null,sourceRevision:edition.source_revision??null,headers:{}}}
async function verifyMediaRequest(env,edition,u){const exp=Number(u.searchParams.get('exp'));const sig=u.searchParams.get('sig')||'';if(!Number.isInteger(exp)||exp<Math.floor(Date.now()/1000)||exp>Math.floor(Date.now()/1000)+MEDIA_TTL_SECONDS+30)return false;return verifyHmacB64url(env.MEDIA_SIGNING_SECRET,`${edition.id}.${exp}.${edition.source_revision??''}`,sig)}

export async function handle(req,env){
  const u=new URL(req.url);const store=env.DB?new D1Store(env.DB):null;
  if(req.method==='GET'&&u.pathname==='/v1/health')return json({ok:true,service:'lume',protocol:1});
  if(req.method==='GET'&&u.pathname==='/v1/ready'){
    const config=validateRuntimeConfig(env);let state={ok:false,durable:false,revision:0};try{if(store)state=await store.readiness()}catch{}
    const ok=config.ok&&state.ok&&(!config.production||state.durable);return json({ok,service:'lume',protocol:1,durable:state.durable,revision:state.revision,configOk:config.ok},ok?200:503);
  }
  if(req.method==='POST'&&u.pathname==='/v1/auth/login'){
    let body;try{body=await req.json()}catch{return json({error:'invalid_json'},400)}
    const username=normalizeUsername(body?.username);if(!await rateLimitLogin(env,username))return json({error:'too_many_attempts'},429,{'retry-after':'60'});
    if(!store||!secretStrong(env.AUTH_SECRET)||!secretStrong(env.PASSWORD_PEPPER))return json({error:'auth_not_configured'},503);
    const account=await store.getAccount(username);const verifier=account?.password_verifier||await hmacB64url(env.PASSWORD_PEPPER,'__invalid_account__');
    const valid=await verifyPasswordVerifier(env.PASSWORD_PEPPER,String(body?.password??''),verifier);
    if(!account||!valid||account.disabled)return json({error:'invalid_credentials'},401);
    const expiresAt=Date.now()+SESSION_MS;const token=await signSession({v:1,sub:account.profile_id,role:account.role,iat:Date.now(),exp:expiresAt},env.AUTH_SECRET);
    return json({token,profileId:account.profile_id,role:account.role,expiresAt});
  }
  const mediaFile=u.pathname.match(/^\/v1\/media\/([^/]+)\/file$/);
  if(mediaFile&&(req.method==='GET'||req.method==='HEAD')){
    if(!store)return json({error:'backend_not_configured'},503);const edition=await store.getEdition(safePath(mediaFile[1]));if(!edition)return json({error:'media_not_found'},404);
    if(!await verifyMediaRequest(env,edition,u))return json({error:'media_authorization_expired'},403);
    return proxyDriveMedia(req,env,edition.source_file_id);
  }
  const auth=await authenticate(req,env);
  if(req.method==='GET'&&u.pathname==='/v1/bootstrap'){
    if(!auth)return json({error:'unauthorized'},401);if(!store)return json({error:'backend_not_configured'},503);
    const b=await store.bootstrap(u.searchParams.get('since'));if(b.notModified)return new Response(null,{status:304,headers:{'cache-control':'no-store'}});return json(b);
  }
  if(req.method==='POST'&&u.pathname==='/v1/admin/catalog'){
    if(!auth)return json({error:'unauthorized'},401);if(auth.role!=='admin')return json({error:'forbidden'},403);if(!store)return json({error:'backend_not_configured'},503);
    let body;try{body=await req.json()}catch{return json({error:'invalid_json'},400)}
    try{await applyCatalogManifest(env.DB,body);return json({revision:await store.getRevision()})}catch(e){return json({error:'catalog_rejected',detail:String(e?.message||e)},409)}
  }
  const media=u.pathname.match(/^\/v1\/media\/([^/]+)$/);
  if(media&&req.method==='GET'){
    if(!auth)return json({error:'unauthorized'},401);if(!store)return json({error:'backend_not_configured'},503);
    const edition=await store.getEdition(safePath(media[1]));return edition?json(await mediaDescriptor(req,env,edition)):json({error:'media_not_found'},404);
  }
  const progress=u.pathname.match(/^\/v1\/profiles\/([^/]+)\/progress\/([^/]+)$/);
  if(progress&&req.method==='PUT'){
    const profile=safePath(progress[1]),edition=safePath(progress[2]);if(!auth)return json({error:'unauthorized'},401);if(!canAccessProfile(auth,profile))return json({error:'forbidden'},403);
    let body;try{body=await req.json()}catch{return json({error:'invalid_json'},400)}
    if(!body.opId||!body.locator||typeof body.percent!=='number'||body.percent<0||body.percent>1||body.clientUpdatedAt==null)return json({error:'invalid_progress'},400);
    try{return json(await putProgressD1(store,profile,edition,body))}catch(e){return json({error:'invalid_progress',detail:String(e?.message||e)},400)}
  }
  const sync=u.pathname.match(/^\/v1\/profiles\/([^/]+)\/sync$/);
  if(sync&&req.method==='GET'){
    const profile=safePath(sync[1]);if(!auth)return json({error:'unauthorized'},401);if(!canAccessProfile(auth,profile))return json({error:'forbidden'},403);
    return json(await store.sync(profile,u.searchParams.get('cursor')||'0'));
  }
  if(sync&&req.method==='POST'){
    const profile=safePath(sync[1]);if(!auth)return json({error:'unauthorized'},401);if(!canAccessProfile(auth,profile))return json({error:'forbidden'},403);
    let body;try{body=await req.json()}catch{return json({error:'invalid_json'},400)}
    const operations=Array.isArray(body.ops)?body.ops:(Array.isArray(body.operations)?body.operations:[]);const ack=[],rejected=[];
    for(const op of operations){
      const kind=op?.kind??op?.type;
      if(kind!=='progress'){if(op?.opId)rejected.push({opId:op.opId,reason:'unsupported operation'});continue;}
      if(!op?.editionId||!op?.opId){if(op?.opId)rejected.push({opId:op.opId,reason:'invalid progress operation'});continue;}
      try{await putProgressD1(store,profile,op.editionId,op);ack.push(op.opId)}catch(e){rejected.push({opId:op.opId,reason:String(e?.message||'invalid operation')})}
    }
    try{const delta=await store.sync(profile,body.cursor??'0');return json({...delta,ack,rejected})}catch(e){return json({error:'sync_conflict',detail:String(e?.message||e)},409)}
  }
  return json({error:'not_found'},404);
}
export default {fetch:handle};
