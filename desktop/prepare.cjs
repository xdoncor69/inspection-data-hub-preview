'use strict';
const fs=require('node:fs');
const path=require('node:path');
const candidates=[path.join(__dirname,'..','preview','index.html'),path.join(__dirname,'..','index.html')];
const source=candidates.find(p=>fs.existsSync(p));
if(!source)throw new Error('Current Inspection Data Hub HTML not found.');
fs.copyFileSync(source,path.join(__dirname,'index.html'));
