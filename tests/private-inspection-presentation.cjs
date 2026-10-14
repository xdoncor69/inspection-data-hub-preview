const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(process.argv[2]||(fs.existsSync('preview/index.html')?'preview/index.html':'index.html'),'utf8');
const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)].filter(m=>!m[1].includes('src='));for(const s of scripts)new vm.Script(s[2]);
const context={window:{InspectionCloud:{isAdministrator:()=>false,isPORowVerified:r=>!!r.verifiedAt}},administrator:false};
vm.createContext(context);vm.runInContext(html.match(/function approvedEvidenceHTML\(\)\{[^\n]+/)[0],context);
for(const admin of [false,true]){context.administrator=admin;assert.equal(vm.runInContext("approvedEvidenceHTML({rows:[{item:'001',plant:'P81A',verifiedAt:'2026-01-01',verifiedBy:'SECRET'}]})",context),'');}
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
Object.assign(context,{safe:esc,poDisplayProduct:()=>({brand:'Brand',pack:'12',category:'Meat'}),poCatalogBadge:()=>'',estPriorityCell:()=>'<span>High</span>'});
context.window.InspectionProduct={packSize:v=>v,classLabel:v=>v};vm.runInContext(html.match(/function mobileInspectionHTML\(p\)\{[^\n]+/)[0],context);
for(const admin of [false,true]){
 context.window.InspectionCloud.isAdministrator=()=>admin;context.p={rows:[{item:'001',description:'Ham',plant:'P81A',verifiedAt:'2026-01-01',verifiedBy:'SECRET'}]};
 const a=vm.runInContext('mobileInspectionHTML(p)',context);context.p.rows[0].verifiedAt='';const b=vm.runInContext('mobileInspectionHTML(p)',context);assert.equal(a,b);assert(!a.includes('2026-01-01'));assert(!a.includes('SECRET'));assert(!/not physically|physically checked/i.test(a));
}
Object.assign(context,{fixedEST:()=>false});context.window.__inspectionItemPriority=()=>({level:'high',reason:'SECRET 230 days since verification'});
vm.runInContext(html.match(/function estPriorityCell\(item\)\{[\s\S]*?\n\}/)[0],context);const priorityHTML=vm.runInContext("estPriorityCell('001')",context);assert(priorityHTML.includes('High'));assert(!priorityHTML.includes('SECRET'));assert(!priorityHTML.includes('230'));assert(!priorityHTML.includes('title='));
const archive=html.slice(html.indexOf('function renderPOArchive(){'),html.indexOf('\nfunction deletePrivateDraft'));assert(!archive.includes('verifiedAt'));assert(!archive.includes('verifiedEsts'));
assert(!html.includes('+approvedEvidenceHTML(a.snapshot)'));
for(const text of ['Inspection evidence','Physically checked','Not physically checked','Not individually verified','Weeks since check','days without verification','Last observed:','MOST RECENT CONFIRMED EST','NOT VERIFIED'])assert(!html.includes(text),text);
assert(!html.includes('id="verification-rows"'));
const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{innerHTML:'',textContent:'',replaceChildren(){this.innerHTML='';}});return nodes.get(id);};
Object.assign(context,{$:node,selected:{item:'001',plant:'P81A'},summary:()=>({all:[{date:'2026-01-01',est:'P81A'}],latest:{date:'2026-01-01',est:'P81A'}}),priority:()=>({level:'high',label:'SECRET',reason:'230 days'}),stableItems:new Set(),esc,verifyModal:()=>{},admin:()=>true});
const renderStart=html.indexOf('function render(){\n const x=typeof selected'),renderEnd=html.indexOf('\nfunction verifyModal(){',renderStart);assert(renderStart>0);vm.runInContext(html.slice(renderStart,renderEnd),context);vm.runInContext('render()',context);
assert(node('est-summary-design').innerHTML.includes('High priority'));assert(!/230|SECRET|2026-01-01/.test(node('est-summary-design').innerHTML));assert.equal(node('plant-label').textContent,'EST');
context.admin=()=>false;vm.runInContext('render()',context);assert.equal(node('est-summary-design').innerHTML,'');
// Execute the actual overview exporter; underlying history must not enter any export cell.
context.el=node;context.invoiceData=()=>({po:'001',customer:'Customer',rows:[{item:'01',brand:'B',plant:'P81A',description:'Ham',pack:'12',receivedQuantity:'',level:'high',s:{date:'2026-01-01',latest:'SECRET'},weeks:230}]});
let csv;context.saveCSV=(name,rows)=>{csv=rows;};context.alert=()=>{};const start=html.indexOf('el("invoice-export").onclick=()=>{'),end=html.indexOf('el("invoice-print").onclick=',start);vm.runInContext(html.slice(start,end),context);node('invoice-export').onclick();
assert(csv);assert(!JSON.stringify(csv).includes('SECRET'));assert(!JSON.stringify(csv).includes('2026-01-01'));assert(!JSON.stringify(csv).includes('230'));assert.equal(csv[0].length,csv[1].length);
console.log('PASS: '+scripts.length+' scripts compile; both roles emit no evidence, checked/un-checked mobile rows render equally, priority has no elapsed-time tooltip, profile and CSV contain no dates/status/counters, original writer/priority data retained.');
