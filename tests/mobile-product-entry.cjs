const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const h=fs.readFileSync(process.argv[2]||'index.html','utf8');
const code=h.slice(h.indexOf('function setQueryCellEditing('),h.indexOf('let batchEditing=false'));
const c={safe:s=>String(s).replaceAll('"','&quot;')};vm.createContext(c);vm.runInContext(code,c);
for(const category of ['Meat','Poultry','','Unknown']){
 const markup=c.queryCategoryCell({item:'0001',category});
 assert.match(markup,/<select[^>]+disabled/);assert.match(markup,/data-field="category"/);
 assert.equal((markup.match(/<option/g)||[]).length,3);
 assert.match(markup,category==='Meat'||category==='Poultry'?new RegExp('value="'+category+'" selected'): /value="" disabled selected/);
 assert(!markup.includes('value="Unknown"'));assert(!markup.includes('Dairy'));
}
const select={tagName:'SELECT',disabled:true},input={tagName:'INPUT',readOnly:true};
for(const editing of [true,false,true,false]){c.setQueryCellEditing(select,editing);c.setQueryCellEditing(input,editing);assert.equal(select.disabled,!editing);assert.equal(input.readOnly,!editing);}
assert.match(h,/n=>setQueryCellEditing\(n,true\)/);
assert.match(h,/setQueryCellEditing\(input,editing\)/);
const roleStart=h.indexOf("document.querySelectorAll('.iq-cell').forEach(el=>{");
const roleEnd=h.indexOf('\n\n',roleStart),roleCode=h.slice(roleStart,roleEnd);
for(const administrator of [true,false])for(const editing of [true,false]){
 const node={tagName:'SELECT',disabled:false,closest:()=>({dataset:{iqEditing:String(editing)}})};
 vm.runInNewContext(roleCode,{administrator,document:{querySelectorAll:()=>[node]}});
 assert.equal(node.disabled,!administrator||!editing);
}
const condition=h.match(/else if\(el.matches\('select'\)\)el.disabled=([^;]+);/)[1];
for(const editable of [true,false])for(const administrator of [true,false])for(const editing of [true,false]){
 const el={matches:s=>s==='.iq-cell',closest:()=>({dataset:{iqEditing:String(editing)}})};
 assert.equal(vm.runInNewContext(condition,{editable,administrator,el}),!editable||!administrator||!editing);
}
const css=h.match(/<style id="mobile-entry-no-focus-zoom">([\s\S]*?)<\/style>/)[1];
assert.match(css,/max-width:900px/);assert.match(css,/any-pointer:coarse/);assert.match(css,/body textarea,body select\{font-size:16px!important\}/);
const viewport=h.match(/<meta name="viewport"[^>]+>/)[0];
assert(!/maximum-scale|user-scalable/.test(viewport));assert.match(viewport,/width=device-width, initial-scale=1/);
console.log('PASS: mobile 16px entry CSS, pinch zoom retained, category options and placeholder, individual/batch edit hooks, readonly and admin/connection permissions.');
