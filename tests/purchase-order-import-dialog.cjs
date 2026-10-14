const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const h=fs.readFileSync(process.argv[2]||'index.html','utf8');
const nodes={};function node(){return {value:'',classList:{add(){}},focus(){this.focused=true}};}
for(const k of ['po-import-dialog','order-import-po','po-import-number','po-import-close','po-import-customer','po-import-summary','po-import-status'])nodes[k]=node();
const events=[];const dialog=nodes['po-import-dialog'];dialog.showModal=()=>events.push('open');dialog.close=()=>events.push('close');dialog.addEventListener=(k,f)=>dialog[k]=f;
let allowed=true,resets=0;const c={el:id=>nodes[id],window:{InspectionCloud:{canEdit:()=>allowed,deny:()=>events.push('deny'),hasApprovedPO:()=>false,requireClient:()=>({id:'c',name:'Customer'}),layoutAccount:()=> 'account'}},resetOrderImport:()=>resets++};vm.createContext(c);
vm.runInContext(h.slice(h.indexOf('const importDialog=el('),h.indexOf('function parseDelimited')),c);
nodes['order-import-po'].onclick();assert.equal(resets,1);assert.equal(events.at(-1),'open');assert(nodes['po-import-number'].focused);
nodes['po-import-close'].onclick();assert.equal(events.at(-1),'close');assert.equal(resets,2);
dialog.cancel();assert.equal(resets,3);allowed=false;nodes['order-import-po'].onclick();assert.equal(events.at(-1),'deny');assert.equal(resets,3);
let conflict=false,callbacks,persistOK=false;nodes['po-import-number'].value='000123';nodes['po-import-customer'].value='Customer';
Object.assign(c,{clean:x=>String(x).trim(),findExistingPO:()=>conflict,offerExistingPO:(n,onNew,onOpen)=>{events.push('conflict');callbacks={onNew,onOpen}},setStatus:()=>{},sourceRows:[],preview:[{item:'0007',sourceProduct:{description:'Source description',plant:'',notes:'',pack:'6 x 8oz'}}],rowFor:p=>({...p}),fileName:'source.xlsx',confirm:()=>true,alert:()=>{},invoices:[],persistPOWorkspace:()=>persistOK,activatePO:()=>events.push('activate'),renderPOArchive:()=>{}});
const start=h.indexOf('el("po-import-create").onclick=');const end=h.indexOf('\n})();',start);nodes['po-import-create']=node();vm.runInContext(h.slice(start,end),c);
conflict=true;nodes['po-import-create'].onclick();assert.deepEqual(events.slice(-2),['close','conflict']);const before=resets;callbacks.onNew();assert.equal(events.at(-1),'open');assert.equal(resets,before);assert.equal(c.preview.length,1);callbacks.onOpen();assert.equal(resets,before+1);
conflict=false;nodes['po-import-number'].value='000123';let closed=events.filter(x=>x==='close').length;nodes['po-import-create'].onclick();assert.equal(c.invoices.length,0);assert.equal(events.filter(x=>x==='close').length,closed);
persistOK=true;nodes['po-import-create'].onclick();assert.equal(c.invoices.length,1);assert.equal(c.invoices[0].po,'000123');assert.equal(c.invoices[0].rows[0].item,'0007');assert.equal(c.invoices[0].rows[0].importedProduct.pack,'6 x 8oz');assert.equal(events.filter(x=>x==='close').length,closed+1);
assert(h.includes("document.getElementById('order-import-delivery').onclick=()=>openSAPDelivery(null);"));assert(!h.includes('function setOrderImportMode'));assert(!h.includes('id="po-import-toggle"'));
console.log('PASS: guarded modal entry, close/cancel, duplicate handoff/reopen, failed-save retention, successful draft handoff and unchanged delivery launcher.');
