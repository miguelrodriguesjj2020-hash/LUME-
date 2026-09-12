'use strict';
const crypto=require('crypto');
const [username,role,profileId]=process.argv.slice(2);
const password=process.env.LUME_NEW_PASSWORD;
if(!username||!['admin','consumer'].includes(role)||!profileId||!password)throw new Error('usage: LUME_NEW_PASSWORD=... node make_user.js <username> <admin|consumer> <profileId>');
if(password.length<10)throw new Error('password must be at least 10 characters');
const salt=crypto.randomBytes(16).toString('hex');
const passwordHash=crypto.scryptSync(password,salt,32).toString('hex');
process.stdout.write(JSON.stringify({username,salt,passwordHash,role,profileId}));
