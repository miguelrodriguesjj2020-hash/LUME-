import {randomBytes,randomUUID} from 'node:crypto';
import {passwordVerifier,normalizeUsername} from '../src/crypto.mjs';
const [usernameRaw,role='consumer',profileIdRaw,passwordRaw]=process.argv.slice(2);
if(!usernameRaw)throw new Error('usage: LUME_PASSWORD_PEPPER=... node tool/create_account.mjs <username> [consumer|admin] [profileId] [password]');
if(!['consumer','admin'].includes(role))throw new Error('role must be consumer or admin');
const pepper=process.env.LUME_PASSWORD_PEPPER;if(!pepper||pepper.length<32)throw new Error('LUME_PASSWORD_PEPPER must be at least 32 chars');
const username=normalizeUsername(usernameRaw),profileId=profileIdRaw||`profile-${randomUUID()}`;
const password=passwordRaw||randomBytes(18).toString('base64url');if(password.length<16)throw new Error('password must be at least 16 characters');
const verifier=await passwordVerifier(pepper,password),id=`acct-${randomUUID()}`,now=new Date().toISOString();
function q(v){return `'${String(v).replaceAll("'","''")}'`}
console.log(`INSERT INTO profiles(id,account_id,name,created_at,updated_at) VALUES(${q(profileId)},${q(id)},${q(username)},${q(now)},${q(now)}) ON CONFLICT(id) DO NOTHING;`);
console.log(`INSERT INTO accounts(id,username,password_verifier,role,profile_id,disabled,created_at,updated_at) VALUES(${q(id)},${q(username)},${q(verifier)},${q(role)},${q(profileId)},0,${q(now)},${q(now)});`);
console.error(`USERNAME=${username}`);console.error(`PASSWORD=${password}`);console.error(`PROFILE_ID=${profileId}`);
