#!/usr/bin/env python3
"""Root-approved C33 private DXVK pair only; no wake/device/container/VM actions."""
import argparse,importlib.util,json,os,re,shutil,stat,sys,tarfile
from pathlib import Path
sys.dont_write_bytecode=True
import c15_build_common as c
spec=importlib.util.spec_from_file_location('c15_reference',Path(__file__).with_name('c15_reference_build.py'))
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
ROOT=Path('/home/igul/codex-fp32-c33-dxvk-r1')
def original():
 return {'states':{k:c.repo_state(p)for k,p in c.REPOS.items()},'sources':{k:c.source_inventory(p,k)for k,p in c.REPOS.items()},'deps':{k:c.repo_state(p)for k,p in c.DEPENDENCIES.items()}}
def owned(root,owner):
 c.no_symlink(root);s=root.stat()
 if root!=ROOT or s.st_uid!=os.getuid()or s.st_mode&0o077 or not re.fullmatch('codex-[a-z0-9-]+',owner):raise RuntimeError('exact owned0700 root/owner required')
 if Path('/home/igul/.cache/bouw-lock.d/owner').read_text().split()[0]!=owner:raise RuntimeError('own lease missing')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,required=True);ap.add_argument('--lease-owner',required=True);ap.add_argument('--packet-sha256',required=True);a=ap.parse_args();owned(a.root,a.lease_owner)
 stage=a.root/'stage-c33-r1';c.no_symlink(stage);mp=stage/'packet-manifest.json'
 if c.sha(mp)!=a.packet_sha256:raise RuntimeError('packet pin mismatch')
 packet=json.loads(mp.read_text())
 for e in packet['files']:
  p=stage/c.safe_relative(e['path']);c.no_symlink(p)
  if c.sha(p)!=e['sha256']or p.stat().st_size!=e['bytes']:raise RuntimeError('stage mismatch '+e['path'])
 plan=json.loads((stage/'build-plan.json').read_text());recipe=json.loads((stage/'fresh-dxvk-recipe.json').read_text());baseline=json.loads((stage/'baseline-dxvk-inventory.json').read_text());source=plan['source']
 if plan['privateRoot']!=str(ROOT)or c.sha(stage/'source-inputs.tar.gz')!=plan['sourceArchiveSha256']:raise RuntimeError('root/archive mismatch')
 for n in ('source','dxvk-build','artifact','retrieval.tar.gz','retrieval-transport.json'):
  if(a.root/n).exists()or(a.root/n).is_symlink():raise RuntimeError('fresh path exists '+n)
 artifact=a.root/'artifact';artifact.mkdir(mode=0o700);before=None;private=None;success=False;error=None
 try:
  if __import__('subprocess').check_output(['/home/igul/winbuild/vm.sh','status'],text=True).strip()!='uit':raise RuntimeError('Windows must stay off')
  before={'original':original(),'protected':c.verify_protected(plan),'oldPrivateDxvk':c.source_inventory(Path('/home/igul/codex-c15-host-r7/source/dxvk'),'dxvk')}
  if before['oldPrivateDxvk']!=baseline:raise RuntimeError('actual F19 private source changed')
  c.write_new(artifact/'before.json',before);src=a.root/'source/dxvk';src.mkdir(parents=True,mode=0o700)
  with tarfile.open(stage/'source-inputs.tar.gz')as t:
   members={m.name:m for m in t.getmembers()}
   for n,e in baseline.items():
    c.safe_relative(n);m=members['source/dxvk/'+n]
    if e['kind']!='file'or not m.isfile()or m.size!=e['bytes']:raise RuntimeError('nonregular source '+n)
    p=src/n;p.parent.mkdir(parents=True,exist_ok=True)
    with p.open('xb')as out:shutil.copyfileobj(t.extractfile(m),out)
    p.chmod(e['mode'])
    if c.sha(p)!=e['sha256']:raise RuntimeError('archive source mismatch '+n)
  target=src/source['path']
  if c.sha(target)!=source['baselineSha256'].lower()or c.sha(stage/'dxvk_shader_ir.cpp')!=source['postSha256'].lower():raise RuntimeError('single patch pin mismatch')
  shutil.copyfile(stage/'dxvk_shader_ir.cpp',target);os.utime(target,None)
  private=c.source_inventory(src,'dxvk');expected=json.loads(json.dumps(baseline));expected[source['path']]['sha256']=source['postSha256'].lower();expected[source['path']]['bytes']=target.stat().st_size
  if private!=expected:raise RuntimeError('only one source delta allowed')
  c.write_new(artifact/'compiler-source-inventory.json',private)
  env=dict(os.environ);env['PATH']=recipe['toolResolution']['PATHPrefix']+os.pathsep+env.get('PATH','');tools={}
  for n in ('meson','ninja','patchelf'):
   p=shutil.which(n,path=env['PATH'])
   if not p:raise RuntimeError('existing tool missing '+n)
   tools[n]=f.tool_identity(p);f.capture([p,'--version'],artifact/(n+'-version.txt'),env=env)
  if(artifact/'meson-version.txt').read_text().strip()!=recipe['toolResolution']['expectedMesonVersion']or(artifact/'ninja-version.txt').read_text().strip()!=recipe['toolResolution']['expectedNinjaVersion']:raise RuntimeError('compiler workflow version changed')
  llvm=c.NDK/'toolchains/llvm/prebuilt/linux-x86_64/bin'
  for n in ('aarch64-linux-android30-clang','aarch64-linux-android30-clang++','llvm-ar','llvm-strip','llvm-ranlib','llvm-readelf'):tools[n]=f.tool_identity(llvm/n,c.NDK)
  f.capture([str(llvm/'aarch64-linux-android30-clang++'),'--version'],artifact/'clang-version.txt');c.write_new(artifact/'tools.json',tools)
  owned(a.root,a.lease_owner)
  if c.verify_protected(plan)!=before['protected']:raise RuntimeError('old outputs changed before compiler')
  print('C33_FRESH_DXVK_CONFIGURE_START',flush=True);f.command(recipe['setupArgv'],artifact/'dxvk-setup.log',env=env)
  c.write_new(artifact/'setup-verified.json',f.verify_dxvk_setup(a.root/'dxvk-build',recipe));c.copy_new(a.root/'dxvk-build/compile_commands.json',artifact/'compile_commands.json');f.capture([tools['ninja']['resolved'],'-C',str(a.root/'dxvk-build'),'-t','commands'],artifact/'ninja-commands.txt',env=env)
  print('C33_ACTUAL_FRESH_MATCHED_DXVK_COMPILE_START',flush=True);f.command(recipe['buildArgv'],artifact/'dxvk-build.log',env=env);f.capture([tools['ninja']['resolved'],'-C',str(a.root/'dxvk-build'),'-t','deps'],artifact/'ninja-deps.txt',env=env)
  (artifact/'dxvk').mkdir();outputs=[]
  for item in recipe['postBuildPrivateOnly']:
   binary=Path(item['input']);f.checked_elf(binary);unstripped=Path(item['copyUnstrippedTo']);packed=Path(item['copyPackedTo']);c.copy_new(binary,unstripped);c.copy_new(binary,packed)
   f.command(item['stripArgv'],artifact/(packed.name+'.strip.log'),env=env);f.command(item['rpathArgv'],artifact/(packed.name+'.rpath.log'),env=env);f.capture(item['inspectArgv'],artifact/(packed.name+'.elf.txt'),env=env)
   if '$ORIGIN'not in(artifact/(packed.name+'.elf.txt')).read_text():raise RuntimeError('literal RPATH missing')
   outputs.append({'name':packed.name,'bytes':packed.stat().st_size,'sha256':c.sha(packed),'unstrippedBytes':unstripped.stat().st_size,'unstrippedSha256':c.sha(unstripped)})
  if{e['name']for e in outputs}!={'libdxvk_d3d11.so','libdxvk_dxgi.so'}:raise RuntimeError('pair incomplete')
  c.write_new(artifact/'artifacts.json',{'status':'BUILT_NOT_DEPLOYED','files':outputs});c.write_new(artifact/'all-new-objects.json',f.object_manifest(a.root/'dxvk-build'))
  for n in ('meson-info','meson-logs'):shutil.copytree(a.root/'dxvk-build'/n,artifact/n)
  for n in ('version.h','buildenv.h'):
   if(a.root/'dxvk-build'/n).is_file():c.copy_new(a.root/'dxvk-build'/n,artifact/n)
  with tarfile.open(artifact/'source-inputs.tar.gz','x:gz')as t:
   for n in private:t.add(src/n,arcname='source/dxvk/'+n,recursive=False)
  success=True
 except Exception as exc:error=str(exc)
 finally:
  checks={}
  try:
   if before is not None:
    checks={'originalSourcesUnchanged':original()==before['original'],'allOldArtifactsUnchanged':c.verify_protected(plan)==before['protected'],'oldF19PrivateSourceUnchanged':c.source_inventory(Path('/home/igul/codex-c15-host-r7/source/dxvk'),'dxvk')==before['oldPrivateDxvk']}
    if private is not None:checks['newCompilerSourceUnchanged']=c.source_inventory(a.root/'source/dxvk','dxvk')==private
    if not all(checks.values()):raise RuntimeError('protection failure')
  except Exception as exc:success=False;error=(error+'; 'if error else'')+str(exc)
  c.write_new(artifact/'protection-after.json',checks);c.write_new(artifact/'build-result.json',{'success':success,'error':error,'noDeviceOrVMAction':True,'noContainerOrMountUsed':True,'packetSha256':a.packet_sha256})
  for e in packet['files']:
   dest=artifact/'reviewed-packet'/e['path'];dest.parent.mkdir(parents=True,exist_ok=True);c.copy_new(stage/e['path'],dest)
  c.copy_new(mp,artifact/'reviewed-packet/packet-manifest.json');entries=[]
  for p in sorted(artifact.rglob('*')):
   if p.is_file():c.no_symlink(p);entries.append({'path':str(p.relative_to(artifact)),'bytes':p.stat().st_size,'sha256':c.sha(p)})
  c.write_new(artifact/'retrieval-manifest.json',{'files':entries,'scope':'Private DXVK matchedpair build evidence only'})
  with tarfile.open(a.root/'retrieval.tar.gz','x:gz')as t:
   for e in entries:t.add(artifact/e['path'],arcname=e['path'],recursive=False)
   t.add(artifact/'retrieval-manifest.json',arcname='retrieval-manifest.json',recursive=False)
  c.write_new(a.root/'retrieval-transport.json',{'path':str(a.root/'retrieval.tar.gz'),'bytes':(a.root/'retrieval.tar.gz').stat().st_size,'sha256':c.sha(a.root/'retrieval.tar.gz')})
 print((a.root/'retrieval-transport.json').read_text(),flush=True)
 if not success:raise SystemExit('C33_BUILD_FAILED_PRESERVED: '+str(error))
if __name__=='__main__':main()
