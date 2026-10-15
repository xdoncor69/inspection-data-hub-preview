const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const h=fs.readFileSync(process.argv[2]||'index.html','utf8');
for(const s of h.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g))if(!s[1].includes('src='))new vm.Script(s[2]);
const nodes={};function el(id){return nodes[id]??={value:'',disabled:false,hidden:false,textContent:'',innerHTML:'',classList:{toggle(){}},events:{},addEventListener(k,v){this.events[k]=v;},querySelectorAll:()=>[]};}
const base={item:'0001',brand:'Brand',description:'Ham',category:'Meat',pack:'6 x 8oz',family:'Deli',plant:'P1'};
let admin=true,adds=[],updates=[],pending=false,refresh=async()=>[base];
const c={document:{getElementById:el},window:{InspectionCloud:{itemKey:v=>String(v??'').trim(),exactCatalogItem:(all,id)=>all.find(p=>p.item===id),refreshCatalog:()=>refresh(),catalogError:e=>'Catalog query error: '+e.message,isAdministrator:()=>admin,canEdit:()=>true,deny(){},saveCatalogResults:async rows=>{updates.push(rows);return {pending,count:rows.length}},addImportedCatalog:async rows=>{adds.push(rows);return !pending}},InspectionProduct:{visible:p=>p.category!=='Dairy',classLabel:v=>v||'',packSize:(a,b)=>[...new Set([a,b].filter(Boolean))].join(' · ')},dispatchEvent(){}},demo:[base],productDescription:v=>String(v||''),confirm:()=>true,CustomEvent:function(){},setTimeout:()=>1,clearTimeout(){}};
vm.createContext(c);const start=h.indexOf('const el=id=>document.getElementById(id);',h.indexOf('/* Product catalog import:')),end=h.indexOf('const mappings={',start);
vm.runInContext(h.slice(start,end)+';globalThis.rows=()=>staged;',c);
const commitStart=h.indexOf('el("ip-commit").onclick=',end),commitEnd=h.indexOf("document.querySelector('[data-view=\"import\"]')",commitStart);vm.runInContext(h.slice(commitStart,commitEnd),c);
const fresh={item:'0002',brand:'New brand',description:'Turkey',category:'Poultry',pack:'4 x 1lb',plant:'P2'};
function click(dataset){return el('ip-review-rows').onclick({target:{closest:()=>({dataset})}});}
(async()=>{
 c.prepare([{data:{...base,pack:'12 x 8oz'}},{data:fresh},{data:fresh}]);assert.equal(c.reviewBlockers().length,2);assert(el('ip-commit').disabled);
 await el('ip-commit').onclick();assert.equal(adds.length,0);el('ip-accept-new').onclick();assert.equal(c.reviewBlockers().length,2);
 await click({ipResolve:'0'});assert.equal(updates.length,0);
 c.rows()[0].selectedFields.add('pack');await click({ipResolve:'0'});assert.equal(updates.length,1);assert.deepEqual(Object.keys(updates[0][0].changes),['pack']);assert.equal(updates[0][0].changes.pack,'12 x 8oz');assert.equal(base.pack,'6 x 8oz');assert.equal(c.reviewBlockers().length,1);
 await click({ipDismiss:'1'});assert.equal(c.reviewBlockers().length,0);assert(!el('ip-commit').disabled);await el('ip-commit').onclick();assert.equal(adds.length,1);assert.equal(adds[0].length,1);assert.equal(adds[0][0].item,'0002');assert.equal(c.rows().length,0);
 c.prepare([{data:base}]);assert.equal(c.rows()[0].status,'same');assert.equal(c.reviewBlockers().length,1);await click({ipDismiss:'0'});assert.equal(updates.length,1);
 c.prepare([{data:{...base,plant:'P9'}}]);c.rows()[0].selectedFields.add('plant');pending=true;await click({ipResolve:'0'});assert(c.rows()[0].pending);assert.equal(c.reviewBlockers().length,1);assert(el('ip-review-rows').innerHTML.includes('awaiting confirmation'));assert(el('ip-commit').disabled);
 pending=false;let first,second;refresh=()=>new Promise(resolve=>{if(!first)first=resolve;else second=resolve;});el('ip-item').value='0001';const a=c.checkManualItem();el('ip-item').value='0009';const b=c.checkManualItem();second([base]);await b;assert(el('ip-item-status').textContent.includes('No exact record for 0009'));first([base]);await a;assert(el('ip-item-status').textContent.includes('0009'));assert(!el('ip-item-status').textContent.includes('Already in catalog'));
 refresh=async()=>{throw Error('Permission denied')};await c.checkManualItem();assert.match(el('ip-item-status').textContent,/query error.*Permission denied/);assert(!el('ip-item-status').textContent.includes('No exact record'));assert(el('ip-stage-manual').disabled);assert(!el('ip-item-retry').hidden);
 refresh=async()=>[base];el('ip-item').value='0001';await c.checkManualItem();assert(el('ip-item-status').textContent.includes('Already in catalog: 0001'));
 el('ip-brand').value='';el('ip-description').value='';el('ip-category').value='Meat';await el('ip-stage-manual').onclick();assert(c.rows()[0].existing);assert.equal(c.rows()[0].p.item,'0001');assert.equal(c.rows()[0].selectedFields.size,0);
 const count=adds.length;admin=false;c.prepare([{data:fresh}]);await el('ip-commit').onclick();assert.equal(adds.length,count);
 assert(!h.includes('id="ip-skip-existing"'));assert(!h.includes('id="ip-skip-all"'));
 console.log('PASS: exact live lookup with leading zeros, stale-response suppression, query errors versus not-found, early existing-item notice, per-field updates, manual dismissal, duplicate blockers, new-only bulk import, pending locks and admin guards. No browser used.');
})().catch(e=>{console.error(e);process.exitCode=1;});
