'use strict';
const {app,BrowserWindow,protocol,net,session,dialog}=require('electron');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
protocol.registerSchemesAsPrivileged([{scheme:'idh',privileges:{standard:true,secure:true,supportFetchAPI:true,corsEnabled:true,stream:true}}]);
// A fixed per-device profile preserves login independently of temporary portable extraction paths.
app.setPath('userData',path.join(app.getPath('appData'),'InspectionDataHub'));
let mainWindow;
if(!app.requestSingleInstanceLock()){app.quit();}else{
 app.on('second-instance',()=>{if(mainWindow){if(mainWindow.isMinimized())mainWindow.restore();mainWindow.focus();}});
 app.whenReady().then(()=>{
  protocol.handle('idh',request=>{
   const u=new URL(request.url);
   if(u.hostname!=='inspection'||!['/','/index.html'].includes(u.pathname))return new Response('Not found',{status:404});
   return net.fetch(pathToFileURL(path.join(__dirname,'index.html')).href);
  });
  session.defaultSession.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
  mainWindow=new BrowserWindow({width:1380,height:900,minWidth:800,minHeight:600,title:'Inspection Data Hub',backgroundColor:'#eef2f6',webPreferences:{nodeIntegration:false,contextIsolation:true,sandbox:true,webSecurity:true}});
  mainWindow.webContents.setWindowOpenHandler(({url})=>({action:url==='about:blank'?'allow':'deny',overrideBrowserWindowOptions:{webPreferences:{nodeIntegration:false,contextIsolation:true,sandbox:true}}}));
  mainWindow.webContents.on('will-navigate',(event,url)=>{if(!url.startsWith('idh://inspection/'))event.preventDefault();});
  mainWindow.loadURL('idh://inspection/index.html').catch(error=>dialog.showErrorBox('Inspection Data Hub',error.message));
 });
 app.on('window-all-closed',()=>app.quit());
}
