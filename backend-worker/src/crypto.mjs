const te=new TextEncoder();

export function b64urlBytes(bytes){
  let s=''; for(const b of bytes)s+=String.fromCharCode(b);
  return btoa(s).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
}
export function b64urlText(text){return b64urlBytes(te.encode(text));}
export function fromB64url(value){
  const base=value.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(value.length/4)*4,'=');
  const raw=atob(base); return Uint8Array.from(raw,c=>c.charCodeAt(0));
}
async function hmacKey(secret,usage=['sign','verify']){
  return crypto.subtle.importKey('raw',te.encode(secret),{name:'HMAC',hash:'SHA-256'},false,usage);
}
export async function hmacB64url(secret,text){
  const sig=await crypto.subtle.sign('HMAC',await hmacKey(secret,['sign']),te.encode(text));
  return b64urlBytes(new Uint8Array(sig));
}
export async function verifyHmacB64url(secret,text,signature){
  try{return await crypto.subtle.verify('HMAC',await hmacKey(secret,['verify']),fromB64url(signature),te.encode(text));}
  catch{return false;}
}
export function normalizeUsername(value){return String(value??'').normalize('NFKC').trim().toLocaleLowerCase('pt-BR');}
export async function passwordVerifier(pepper,password){return hmacB64url(pepper,String(password));}
export async function verifyPasswordVerifier(pepper,password,verifier){return verifyHmacB64url(pepper,String(password),String(verifier||''));}

export async function signSession(payload,secret){
  const body=b64urlText(JSON.stringify(payload));
  return `${body}.${await hmacB64url(secret,body)}`;
}
export async function verifySession(token,secret,now=Date.now()){
  if(!token||!secret)return null;
  const parts=String(token).split('.'); if(parts.length!==2)return null;
  const [body,sig]=parts; if(!await verifyHmacB64url(secret,body,sig))return null;
  try{
    const payload=JSON.parse(new TextDecoder().decode(fromB64url(body)));
    if(payload.v!==1||!payload.sub||!['consumer','admin'].includes(payload.role))return null;
    if(!Number.isFinite(payload.exp)||payload.exp<=now)return null;
    return {profileId:String(payload.sub),role:payload.role,expiresAt:payload.exp};
  }catch{return null;}
}
