const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const listeners={},db=new Map(),shown=[];
const self={registration:{scope:'https://example.test/app/',showNotification:async(title,options)=>shown.push({title,options}),getNotifications:async()=>[]},clients:{matchAll:async()=>[],openWindow:async()=>{throw Error('Close must not open a window');}},addEventListener:(type,fn)=>listeners[type]=fn};
const context={self,URL,console};vm.createContext(context);vm.runInContext(fs.readFileSync(process.argv[2]||(__dirname+'/../notification-sw.js'),'utf8'),context);
context.testState=async(operation,key,value)=>operation==='get'?db.get(key):db.set(key,value);
vm.runInContext('state=testState',context);
async function event(type,data){let promise;listeners[type]({...data,waitUntil:p=>{promise=p;}});await promise;}
(async()=>{
 db.set('account','admin');
 const payload={id:'event1',recipient:'admin',title:'Pending approval',body:'PO 000123 · Fixture customer — pending approval'};
 await event('push',{data:{json:()=>payload}});
 assert.equal(shown[0].title,'Pending approval');assert.equal(shown[0].options.requireInteraction,true);assert(shown[0].options.actions.some(a=>a.action==='close'));
 assert(shown[0].options.body.includes('000123'));
 db.set('account','other-account');await event('push',{data:{json:()=>payload}});
 assert(!shown[1].options.body.includes('Fixture'));assert(!shown[1].options.body.includes('000123'));
 await event('notificationclick',{action:'close',notification:{data:{id:'event1',uid:'admin'},close(){}}});
 assert.equal(db.get('dismissals')[0].id,'event1');
 console.log('PASS: persistent push option, manual Close, leading zeros, account privacy, durable dismissal queue.');
})();
