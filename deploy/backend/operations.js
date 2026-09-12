const fs=require('fs');
const path=require('path');

function sqliteApi(){
  try{return require('node:sqlite');}
  catch{throw new Error('node:sqlite unavailable');}
}

function verifySqlite(filePath){
  const {DatabaseSync}=sqliteApi();
  const resolved=path.resolve(filePath);
  if(!fs.existsSync(resolved))throw new Error('sqlite file not found');
  const db=new DatabaseSync(resolved,{readOnly:true});
  try{
    const check=db.prepare('PRAGMA quick_check').get();
    if(!check||check.quick_check!=='ok')throw new Error('sqlite integrity check failed');
    const version=db.prepare("SELECT v FROM state WHERE k='schema_version'").get();
    return {ok:true,path:resolved,schemaVersion:version?.v??null};
  }finally{db.close();}
}

function restoreBackup(backupPath,targetPath,{force=false}={}){
  const source=verifySqlite(backupPath).path;
  const target=path.resolve(targetPath);
  fs.mkdirSync(path.dirname(target),{recursive:true});
  if(fs.existsSync(target)&&!force)throw new Error('restore target already exists');
  const temp=`${target}.restore-${process.pid}-${Date.now()}`;
  try{
    fs.copyFileSync(source,temp);
    const fd=fs.openSync(temp,'r');
    try{fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
    verifySqlite(temp);
    if(force&&fs.existsSync(target))fs.rmSync(target,{force:true});
    fs.renameSync(temp,target);
    return verifySqlite(target);
  }catch(e){
    try{fs.rmSync(temp,{force:true});}catch{}
    throw e;
  }
}

if(require.main===module){
  const [cmd,a,b,...rest]=process.argv.slice(2);
  try{
    if(cmd==='verify'){
      console.log(JSON.stringify(verifySqlite(a)));
    }else if(cmd==='restore'){
      console.log(JSON.stringify(restoreBackup(a,b,{force:rest.includes('--force')})));
    }else{
      console.error('usage: node operations.js verify <db> | restore <backup> <target> [--force]');
      process.exitCode=64;
    }
  }catch(e){
    console.error(e.message);
    process.exitCode=1;
  }
}

module.exports={verifySqlite,restoreBackup};
