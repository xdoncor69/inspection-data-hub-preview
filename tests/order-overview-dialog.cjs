const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const h=fs.readFileSync(process.argv[2]||'index.html','utf8');
for(const s of h.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g))if(!s[1].includes('src='))new vm.Script(s[2]);
class Node{
 constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.events={};this.open=false;}
 appendChild(n){if(n.parent)n.parent.children=n.parent.children.filter(x=>x!==n);n.parent=this;this.children.push(n);return n;}
 set innerHTML(s){this.markup=s;if(s.includes('order-overview-content')){for(const id of ['order-overview-close','order-overview-content']){const n=new Node();n.id=id;this.appendChild(n);}}}
 get innerHTML(){return this.markup||'';}
 querySelector(s){return this.querySelectorAll(s)[0]||null;}
 querySelectorAll(s){const out=[];for(const n of this.children){if(s[0]==='#'?n.id===s.slice(1):n.tag==='details'&&n.dataset.orderFold)out.push(n);out.push(...n.querySelectorAll(s));}return out;}
 setAttribute(k,v){this[k]=v;}
 addEventListener(k,v){this.events[k]=v;}
 showModal(){this.open=true;}
 close(){this.open=false;}
}
const body=new Node('body'),doc={body,createElement:t=>new Node(t),getElementById:id=>body.querySelector('#'+id)},ctx={window:{},document:doc};vm.createContext(ctx);
const script=[...h.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)].find(s=>s[1].includes('order-overview-controller'));vm.runInContext(script[2],ctx);const model=ctx.window.InspectionOrderOverview;
const draft=new Node(),approved=new Node();draft.id='po-details';approved.id='approved-po-details';body.appendChild(draft);body.appendChild(approved);
let closedDraft=0,closedApproved=0;model.sync('draft',draft,true,()=>closedDraft++);const dialog=doc.getElementById('order-overview-dialog');assert(dialog.open);assert.equal(draft.parent.id,'order-overview-content');
model.sync('approved',approved,true,()=>closedApproved++);assert.equal(closedDraft,1);assert.equal(draft.hidden,true);assert.equal(approved.hidden,false);assert.equal(draft.parent.id,'order-overview-content');
dialog.events.cancel({preventDefault(){}});assert(!dialog.open);assert.equal(closedApproved,1);
model.sync('approved',approved,true,()=>closedApproved++);model.sync('approved',approved,false);assert(!dialog.open);assert.equal(closedApproved,2);
const fold=new Node('details');fold.dataset.orderFold='po';fold.open=true;approved.appendChild(fold);
assert.deepEqual(Object.keys(model.capture(approved,'A')),[]);const state=model.capture(approved,'A');assert.equal(state.po,true);fold.open=false;model.restore(approved,state);assert(fold.open);model.restore(approved,model.capture(approved,'B'));assert(!fold.open);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const out=new Node(),buttons={};const delivery={id:'d1',delivery_number:'0002',source_file:'file.xlsx',updated_email:'user',updated_at:'2026-10-14',source_path:'protected',rows:[{item:'0007',description:'<script>unsafe</script>',catchWeight:12,receivedQuantity:2,plant:'P1',matched:true},{item:'0007',description:'Repeated',catchWeight:0,receivedQuantity:0,plant:'P1',matched:true}]},po={id:'a1',snapshot:{rows:[{},{},{}]}};
const c={document:{getElementById:id=>id==='approved-po-deliveries'?out:buttons[id]||=(new Node())},window:{InspectionOrderOverview:{capture:()=>({}),restore:()=>{}}},poDeliveries:new Map([['a1',{rows:[delivery]}]]),deliveryCurrent:()=>true,deliveryNotReceived:r=>r.receivedQuantity===0,escapeHTML:esc,openSAPDelivery(){},loadPODeliveries(){},deliveryLoads:new Map()};vm.createContext(c);
vm.runInContext(h.slice(h.indexOf('function renderPODeliveries('),h.indexOf('function openSAPDelivery(')),c);c.renderPODeliveries(po);
assert(out.innerHTML.includes('PO: 3 item lines'));assert(out.innerHTML.includes('Delivery: 2 item lines'));assert(out.innerHTML.includes('<details class="order-lines" data-order-fold="delivery-d1">'));assert(!out.innerHTML.includes('<details open'));assert(out.innerHTML.includes('&lt;script&gt;'));assert(out.innerHTML.includes('data-delivery-export="d1"'));assert.equal((out.innerHTML.match(/<td>0007/g)||[]).length,2);
const renderer=h.slice(h.indexOf('function renderApprovedPOs('),h.indexOf('async function manageApprovedPO'));
assert(renderer.includes('<details class="order-lines" data-order-fold="po">'));assert(!renderer.includes(".appendChild(detailRoot)"));assert(renderer.includes("sync('approved'"));
assert(h.includes("sync('draft',root,true"));assert(h.includes('root.classList.toggle("hidden",false)'));
assert(h.includes('#po-details.mobile-table>.order-lines>.po-mobile-lines'));
assert(h.includes('className="order-action-modal"'));assert(h.includes('if(v!=="purchase-orders")window.InspectionOrderOverview?.dismiss()'));
console.log('PASS: modal open/switch/close/Escape, preserved fold state and reset per order, PO/delivery counts, collapsed repeated delivery lines, escaped content and action hooks. No browser used.');
