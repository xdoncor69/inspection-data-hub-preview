const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(process.argv[2]||'index.html','utf8');
let count=0;for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){if(/src=/.test(match[1])||!match[2].trim())continue;new vm.Script(match[2]);count++;}
const code=html.slice(html.indexOf('function deliveryNumber('),html.indexOf('async function exportDeliveryFile('));
const ctx={window:{},document:{},console};vm.createContext(ctx);vm.runInContext(code,ctx);
const rows=[{item:'001-01',description:'A',catchWeight:45.94,weightUnit:'lb',receivedQuantity:2,plant:'81B'},{item:'002',description:'B',catchWeight:1,weightUnit:'kg',receivedQuantity:'',plant:'471'},{item:'003',description:'C',catchWeight:0,weightUnit:'lb',receivedQuantity:0,plant:'81B'}];
const result=ctx.approvedDeliveryRows({rows});
assert.deepStrictEqual(Array.from(result[0]),['Item Description','Item No.','Catch Weight','Quantity','EST No.']);
assert.equal(result.length,3);assert.equal(result[1][0],'A');assert.equal(result[1][1],'001-01');assert.equal(result[1][2],'45.94 lb');assert.equal(result[2][2],'1 kg');assert.equal(result[2][3],'');
assert.equal(ctx.deliveryFileName({po:'004',deliveryNumber:'005',customerName:'Client A'}),'PO004 - D005 Client A.xlsx');
let matrix;ctx.deliveryExportSheet({utils:{aoa_to_sheet:a=>(matrix=a,{A7:{}})}},result);
assert.equal(matrix.length,7);assert.equal(matrix[6][2],'Total Quantity');assert.equal(matrix[6][3].v,2);assert.equal(matrix[6][3].f,'IF(COUNT(D2:D3)=0,"",SUM(D2:D3))');
console.log('PASS '+count+' inline scripts; fixed export columns, units, blank quantities, zero exclusion, identifiers, filename, three blank rows and quantity total.');
