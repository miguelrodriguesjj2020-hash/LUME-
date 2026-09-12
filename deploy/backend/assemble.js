'use strict';
const fs=require('fs');
const path=require('path');
function assemble(prefix,suffix,target){
  const parts=fs.readdirSync(__dirname).filter(x=>x.startsWith(prefix)&&x.endsWith(suffix)).sort();
  if(!parts.length)throw new Error(`${prefix} fragments missing`);
  const dest=path.join(__dirname,target);
  fs.writeFileSync(dest,Buffer.concat(parts.map(x=>fs.readFileSync(path.join(__dirname,x)))));
  console.log(`assembled ${parts.length} fragments -> ${dest}`);
}
assemble('server.part-','.jsfrag','server.runtime.js');
assemble('admin.part-','.htmlfrag','admin.html');
