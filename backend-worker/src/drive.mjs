import {b64urlText,b64urlBytes} from './crypto.mjs';
const te=new TextEncoder();
let cachedToken=null;

function pemToBytes(pem){
  const b64=String(pem).replace(/\\n/g,'\n').replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g,'');
  const raw=atob(b64);return Uint8Array.from(raw,c=>c.charCodeAt(0));
}
function parseServiceAccount(env){
  let j;try{j=JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON||'');}catch{throw new Error('invalid_google_service_account_json')}
  if(!j?.client_email||!j?.private_key)throw new Error('google_service_account_incomplete');
  return j;
}
export async function getDriveAccessToken(env,fetcher=fetch,now=Date.now()){
  if(cachedToken&&cachedToken.expiresAt>now+60_000)return cachedToken.token;
  const sa=parseServiceAccount(env);const iat=Math.floor(now/1000),exp=iat+3600;
  const header=b64urlText(JSON.stringify({alg:'RS256',typ:'JWT'}));
  const payload=b64urlText(JSON.stringify({iss:sa.client_email,scope:'https://www.googleapis.com/auth/drive.readonly',aud:'https://oauth2.googleapis.com/token',iat,exp}));
  const unsigned=`${header}.${payload}`;
  const key=await crypto.subtle.importKey('pkcs8',pemToBytes(sa.private_key),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,te.encode(unsigned));
  const assertion=`${unsigned}.${b64urlBytes(new Uint8Array(sig))}`;
  const body=new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion});
  const r=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body});
  if(!r.ok)throw new Error(`drive_oauth_${r.status}`);const j=await r.json();if(!j?.access_token)throw new Error('drive_oauth_no_token');
  cachedToken={token:j.access_token,expiresAt:now+(Number(j.expires_in)||3600)*1000}; return cachedToken.token;
}
export function resetDriveTokenCache(){cachedToken=null;}

export async function proxyDriveMedia(request,env,sourceFileId,{fetcher=fetch,tokenProvider=getDriveAccessToken}={}){
  let token;try{token=await tokenProvider(env,fetcher)}catch{return new Response(JSON.stringify({error:'drive_auth_failed'}),{status:502,headers:{'content-type':'application/json','cache-control':'no-store'}})}
  const headers={authorization:`Bearer ${token}`};
  for(const name of ['range','if-range']){const v=request.headers.get(name);if(v)headers[name]=v;}
  let origin;try{origin=await fetcher(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(sourceFileId)}?alt=media&supportsAllDrives=true`,{method:request.method==='HEAD'?'HEAD':'GET',headers,redirect:'follow'});}catch{return new Response(JSON.stringify({error:'media_origin_unreachable'}),{status:502,headers:{'content-type':'application/json','cache-control':'no-store'}})}
  if(!origin.ok&&origin.status!==206){
    const status=origin.status===404?404:502;return new Response(JSON.stringify({error:origin.status===404?'media_origin_not_found':'media_origin_error'}),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
  }
  const out=new Headers({'cache-control':'private, no-store','x-content-type-options':'nosniff'});
  for(const name of ['content-type','content-length','content-range','accept-ranges','etag','last-modified']){const v=origin.headers.get(name);if(v)out.set(name,v);}
  return new Response(request.method==='HEAD'?null:origin.body,{status:origin.status,headers:out});
}
