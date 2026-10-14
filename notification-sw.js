// Notifications only. This service worker does not cache pages, catalog data, or credentials.
'use strict';
const DB='inspection-notifications-v1';
function database(){return new Promise((resolve,reject)=>{const r=indexedDB.open(DB,1);r.onupgradeneeded=()=>r.result.createObjectStore('state');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});}
async function state(operation,key,value){const db=await database();return new Promise((resolve,reject)=>{const tx=db.transaction('state',operation==='get'?'readonly':'readwrite'),store=tx.objectStore('state');const r=operation==='get'?store.get(key):value===undefined?store.delete(key):store.put(value,key);let result;r.onsuccess=()=>{result=r.result;};tx.oncomplete=()=>{db.close();resolve(result);};tx.onerror=()=>{db.close();reject(tx.error);};});}
self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('message',event=>{
 const {type,uid,id}=event.data||{};
 event.waitUntil((async()=>{
  let result=null;
  if(type==='bind-account'){await state('set','account',uid||null);if(!uid){for(const n of await self.registration.getNotifications())n.close();}}
  if(type==='get-dismissals'){const account=await state('get','account');result=account===uid?(await state('get','dismissals')||[]).filter(x=>x.uid===uid):[];}
  if(type==='forget-dismissal'){const rows=await state('get','dismissals')||[];await state('set','dismissals',rows.filter(x=>x.uid!==uid||x.id!==id));}
  event.ports?.[0]?.postMessage(result);
 })());
});
self.addEventListener('push',event=>event.waitUntil((async()=>{
 let payload={};try{payload=event.data?.json()||{};}catch{}
 const uid=await state('get','account');
 const own=uid&&uid===payload.recipient;
 // A delayed message after logout or account switching must never reveal another account's order.
 const title=own?String(payload.title||'Order notification'):'Inspection Data Hub';
 const body=own?String(payload.body||'Open the application to review your notifications.'):'Sign in to review order notifications.';
 const options={body,tag:own?'inspection-'+payload.id:'inspection-sign-in',requireInteraction:true,
  icon:new URL('notification-icon.svg',self.registration.scope).href,
  data:own?{id:payload.id,uid:payload.recipient}:{},
  actions:[{action:'open',title:'Open app'},{action:'close',title:'Close'}]};
 await self.registration.showNotification(title,options);
})()));
async function dismiss(data){
 if(!data?.id||!data.uid)return;
 const rows=await state('get','dismissals')||[];
 if(!rows.some(x=>x.id===data.id&&x.uid===data.uid))await state('set','dismissals',[...rows,{id:data.id,uid:data.uid}].slice(-500));
 for(const client of await self.clients.matchAll({type:'window',includeUncontrolled:true}))client.postMessage({type:'inspection-notification-dismissed'});
}
self.addEventListener('notificationclose',event=>event.waitUntil(dismiss(event.notification.data)));
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  if(event.action==='close'){await dismiss(event.notification.data);return;}
  const url=new URL('./',self.registration.scope);url.searchParams.set('notifications','1');
  const clients=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  const client=clients.find(x=>x.url.startsWith(self.registration.scope));
  if(client){await client.focus();client.postMessage({type:'inspection-open-notifications'});}
  else await self.clients.openWindow(url.href);
 })());
});
