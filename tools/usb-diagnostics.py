import pathlib,asyncio,argparse,json,time

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.house_arrest import HouseArrestService
parser=argparse.ArgumentParser()
parser.add_argument('action',choices=['roots','node','catalogue'])
parser.add_argument('id',nargs='?',type=int)
parser.add_argument('--bundle')
parser.add_argument('--output',type=pathlib.Path,default=pathlib.Path('diagnostics'))
args=parser.parse_args()
directory='/Documents/GlowESPDev'
out=args.output;out.mkdir(parents=True,exist_ok=True)
async def query(afc,request):
 sequence=time.time_ns()//1_000_000;request={**request,'sequence':sequence}
 temp=directory+'/request.tmp';target=directory+'/request.json'
 await afc.set_file_contents(temp,json.dumps(request).encode())
 if await afc.exists(target):raise RuntimeError('Previous diagnostic request is still pending; open the game first')
 await afc.rename(temp,target)
 for _ in range(40):
  await asyncio.sleep(.25)
  path=directory+'/response.json'
  if not await afc.exists(path):continue
  try:response=json.loads(await afc.get_file_contents(path))
  except (json.JSONDecodeError,UnicodeDecodeError):continue
  if response.get('sequence')==sequence:return response['result']
 raise RuntimeError('No diagnostic reply. Keep the game visible and unlocked.')
async def main():
 lockdown=await create_using_usbmux(connection_type='USB',autopair=False)
 try:
  if await lockdown.get_value(key='ProductType')!='iPhone14,5':raise RuntimeError('Wrong USB device')
  async with InstallationProxyService(lockdown) as installation:
   apps=await installation.get_apps(application_type='User')
  candidates=[bundle for bundle,app in apps.items() if app.get('UIFileSharingEnabled') and 'standoff' in (bundle+' '+app.get('CFBundleDisplayName','')+' '+app.get('CFBundleName','')).lower()]
  if args.bundle:
   if args.bundle not in candidates:raise RuntimeError('Requested bundle is not a document-enabled Standoff build')
   bundle=args.bundle
  elif len(candidates)==1:bundle=candidates[0]
  else:raise RuntimeError('Expected one installed diagnostic Standoff build; found '+str(len(candidates)))
  async with await HouseArrestService.create(lockdown,bundle,documents_only=True) as afc:
   if not await afc.exists(directory+'/ready.json'):raise RuntimeError('Start the diagnostic game first')
   ready=json.loads(await afc.get_file_contents(directory+'/ready.json'))
   print('Diagnostic build:',ready.get('version'),'PID:',ready.get('pid'),flush=True)
   if args.action=='catalogue':
    if args.id is None:raise RuntimeError('Catalogue array ID required; query roots first')
    entries=[];start=0
    while start<16384:
     page=await query(afc,{'action':'catalogue','id':args.id,'start':start,'count':256})
     if 'error' in page:raise RuntimeError(page['error'])
     entries.extend(page['entries']);print('Read',page['next'],'/',page['total'],flush=True)
     (out/'cosmetics.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
     if page['next']>=page['total'] or page['next']<=start:break
     start=page['next']
    print('Cosmetics:',len(entries))
   else:
    request={'action':args.action}
    if args.action=='node':
     if args.id is None:raise RuntimeError('Node ID required')
     request['id']=args.id
    result=await query(afc,request)
    (out/(args.action+('-'+str(args.id) if args.id else '')+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(result,ensure_ascii=False))
 finally:await lockdown.close()
asyncio.run(asyncio.wait_for(main(),180))

