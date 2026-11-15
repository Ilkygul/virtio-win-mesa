#!/usr/bin/env python3
"""Reviewed private C15 build only; never wake, deploy, change VM state or power.

Requires a separately Root-approved gate pinned by SHA256, exact existing
phase0 packet, explicit owned lease, and fresh compiler/output directories.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import time
sys.dont_write_bytecode = True
import c15_build_common as common

def command(argv, log, cwd=None, env=None):
    with log.open('x') as stream:
        rc = subprocess.run(argv, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT).returncode
    common.write_new(log.with_suffix(log.suffix+'.result.json'), {'argv': argv, 'exit': rc})
    if rc:
        raise RuntimeError('command failed; preserve ' + str(log))

def capture(argv, path, cwd=None, env=None):
    with path.open('x') as f:
        rc = subprocess.run(argv, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT).returncode
    if rc:
        raise RuntimeError('evidence command failed: ' + str(path))

def checked_elf(path):
    with path.open('rb') as f:
        header = f.read(20)
    if len(header) != 20 or header[:7] != b'\x7fELF\x02\x01\x01' or struct.unpack_from('<H', header, 18)[0] != 183 or struct.unpack_from('<H', header, 16)[0] not in (2,3):
        raise RuntimeError('not ELF64 little-endian AArch64: ' + str(path))

def tool_identity(path, allowed_root=None):
    path = Path(path)
    actual = path.resolve(strict=True)
    if allowed_root is not None and not actual.is_relative_to(allowed_root):
        raise RuntimeError('tool resolves outside approved toolchain')
    return {'path': str(path), 'resolved': str(actual), 'symlink': os.readlink(path) if path.is_symlink() else None,
            'bytes': actual.stat().st_size, 'sha256': common.sha(actual, 512*1024*1024)}

def object_manifest(directory):
    result = []
    for parent, dirs, files in os.walk(directory, followlinks=False):
        for name in files:
            if Path(name).suffix not in ('.o', '.obj', '.a', '.rlib', '.pch', '.gch'):
                continue
            p = Path(parent)/name
            if p.is_symlink() or not p.resolve(strict=True).is_relative_to(directory):
                raise RuntimeError('non-private object refused')
            result.append({'path': str(p.relative_to(directory)), 'bytes': p.stat().st_size, 'sha256': common.sha(p)})
    return result

def compiler_inputs(build, source_root, deps_text, generated_dest):
    result = []
    names = sorted({line[4:] for line in deps_text.splitlines() if line.startswith('    ') and line[4:]})
    if len(names) > 50000:
        raise RuntimeError('compiler dependency count cap')
    for name in names:
        lexical = Path(name) if Path(name).is_absolute() else build/name
        actual = lexical.resolve(strict=True)
        if not any(actual.is_relative_to(p) for p in (build, source_root, common.NDK)):
            raise RuntimeError('compiler read outside private source/build/NDK: ' + name)
        item = {'reported': name, 'resolved': str(actual), 'bytes': actual.stat().st_size,
                'sha256': common.sha(actual, common.MAX_SOURCE_FILE)}
        if actual.is_relative_to(build):
            rel = actual.relative_to(build)
            if actual.suffix not in ('.h', '.hpp', '.inc'):
                raise RuntimeError('unexpected generated compiler input: ' + str(rel))
            dest = generated_dest/rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            if not dest.exists(): common.copy_new(actual, dest)
            elif common.sha(dest) != item['sha256']: raise RuntimeError('generated input collision')
        result.append(item)
    return result

def verify_dxvk_setup(build, recipe):
    options = json.loads((build/'meson-info/intro-buildoptions.json').read_text())
    effective = {x['name']: x['value'] for x in options if x.get('machine') in ('host', 'any')}
    for name, expected in recipe['expectedEffectiveOptions'].items():
        if effective.get(name) != expected:
            raise RuntimeError('fresh effective option differs: ' + name)
    if effective.get('wrap_mode') != 'nodownload':
        raise RuntimeError('offline Meson dependency policy missing')
    info = json.loads((build/'meson-info/intro-projectinfo.json').read_text())
    if info['subprojects'] != recipe['expectedSubprojects']:
        raise RuntimeError('fresh dependency project/version set differs')
    machine = json.loads((build/'meson-info/intro-machines.json').read_text())
    if any(machine['host'].get(k) != v for k, v in {'system': 'android', 'cpu_family': 'aarch64', 'endian': 'little'}.items()):
        raise RuntimeError('fresh target machine differs')
    targets = json.loads((build/'meson-info/intro-targets.json').read_text())
    names = {x['name'] for x in targets}
    if not {'dxvk_d3d11', 'dxvk_dxgi'}.issubset(names):
        raise RuntimeError('matched DXVK targets absent')
    llvm = common.NDK/'toolchains/llvm/prebuilt/linux-x86_64/bin'
    for target in targets:
        for entry in target.get('target_sources', []):
            if entry.get('machine') != 'host' or entry.get('language') not in ('c', 'cpp'):
                continue
            compiler = llvm/('aarch64-linux-android30-clang++' if entry['language']=='cpp' else 'aarch64-linux-android30-clang')
            if entry.get('compiler') != [str(compiler)]:
                raise RuntimeError('compiler/cache/Android API differs from captured baseline')
    # No private compiler may consume an original source/build or an old .a.
    original = (str(common.REPOS['dxvk']), str(common.DXVK_BASE/'build-arm64'))
    blob = json.dumps(targets) + (build/'compile_commands.json').read_text()
    if any(value in blob for value in original):
        raise RuntimeError('fresh compiler inputs still reference original DXVK source/build')
    return {'effectiveOptions': effective, 'projects': info, 'machines': machine,
            'targets': targets, 'matchedPair': True}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--lease-owner', required=True)
    parser.add_argument('--approval-sha256', required=True)
    args = parser.parse_args()
    root, stage = args.root, args.root/'stage-c15-r8'
    common.assert_owned(root, args.lease_owner)
    common.no_symlink(stage)
    stage_stat = stage.stat()
    if not stage.is_dir() or stage_stat.st_uid != os.getuid() or stage_stat.st_mode & 0o077:
        raise RuntimeError('fresh caller-owned0700 build stage required')
    gate_path = stage/'c15-build-approval.json'
    if common.sha(gate_path, 1024*1024) != args.approval_sha256.lower():
        raise RuntimeError('Root approval differs')
    gate = json.loads(gate_path.read_text())
    if gate.get('status') != 'ROOT_APPROVED_PRIVATE_C15_BUILD_ONLY' or gate.get('leaseOwner') != args.lease_owner or gate.get('privateRoot') != str(root):
        raise RuntimeError('wrong approval scope/owner/root')
    for name, filename in [('buildScriptSha256', Path(__file__)), ('commonScriptSha256', Path(common.__file__)),
                           ('planSha256', stage/'c15-build-plan.json'), ('recipeSha256', stage/'fresh-dxvk-recipe.json'),
                           ('machineSha256', stage/'android-aarch64.effective.txt')]:
        common.no_symlink(filename)
        if common.sha(filename, 2*1024*1024) != gate.get(name):
            raise RuntimeError('approved script/input hash differs: ' + name)
    if not gate.get('fiveOriginalArtifactsRequired') or not gate.get('freshMatchedDxvkPairRequired') or gate.get('runtimeAuthorized') is not False:
        raise RuntimeError('mandatory build-only matched-pair policy absent')
    if gate.get('classicTargetRouteReviewed') is not True:
        raise RuntimeError('actual Android classic-export route review required; no dead-GBM assumption')
    plan = json.loads((stage/'c15-build-plan.json').read_text())
    recipe = json.loads((stage/'fresh-dxvk-recipe.json').read_text())
    if plan['hostTargets'] != common.HOST_TARGETS or plan['buildImage'] != common.BUILD_IMAGE or plan['runtimeSet'] != common.RUNTIME_SET:
        raise RuntimeError('reviewed C12 targets/image or five-file runtime set differs')
    if {k:len(v) for k,v in plan['files'].items()} != {'rust':4,'virgl':36,'dxvk':6}:
        raise RuntimeError('reviewed combined source set differs')
    if plan['recipeSha256'] != common.sha(stage/'fresh-dxvk-recipe.json') or plan['effectiveMachineSha256'] != common.sha(stage/'android-aarch64.effective.txt'):
        raise RuntimeError('recipe/machine plan link differs')
    if common.sha(Path(plan['phase0']['root'])/'metadata-preflight/packet.json') != plan['phase0']['packetSha256'] or common.sha(Path(plan['phase0']['root'])/'metadata-preflight/manifest.json') != plan['phase0']['manifestSha256']:
        raise RuntimeError('existing phase0 packet differs')
    if common.sha(Path(plan['phase0']['root'])/'stage/host-source-plan.json') != plan['phase0']['sourcePlanSha256']:
        raise RuntimeError('existing phase0 staged plan differs')
    for name in ('source', 'upper', 'work', 'view', 'home', 'artifact', 'dxvk-build', 'before-c15.json', 'host-inner.sh', 'c15-build-result.json'):
        p = root/name
        if p.exists() or p.is_symlink():
            raise RuntimeError('fresh-only C15 output exists: ' + name)
    before = None
    mounted = False
    success = False
    error = None
    try:
        print('C15: checking original sources and five actual baseline artifacts', flush=True)
        states = common.verify_live_inputs(plan, stage)
        protected = common.verify_protected(plan)
        dep = plan['externalSourceDependencies']
        expected_links = [{'source': path, 'dependency': value[0], 'rawLink': value[1]}
                          for path, value in common.RUST_EXTERNAL_LINKS.items()]
        if (dep['links'] != expected_links or dep['copy'] != ['minigbm', 'minijail'] or
            dep['reusePatchedVirglViaAlias'] != 'source/virglrenderer -> virgl' or
            dep['containerROTargets'] != ['/work/crosvm_build/external/minigbm', '/work/crosvm_build/external/minijail', '/work/crosvm_build/external/virglrenderer'] or
            dep['metadataEvidenceSHA256'] != common.sha(stage/'actual-known-source-links.json')):
            raise RuntimeError('exact reviewed three-dependency contract differs')
        dependency_states = {name: common.repo_state(path) for name,path in common.DEPENDENCIES.items()}
        if dependency_states['minigbm'] != {'head': 'b7c93249f685222a524c51403719493cc114ff5d', 'status': ''}:
            raise RuntimeError('actual reviewed minigbm HEAD/clean state changed')
        if dependency_states['minijail'] != {'head': 'ab6cd0f786481e2deecfe6f8563ae0d2416bd460', 'status': ''}:
            raise RuntimeError('actual reviewed minijail HEAD/clean state changed')
        dependency_inventory = {name: common.source_inventory(path, name)
                                for name, path in common.DEPENDENCIES.items()}
        common.rust_generated_inputs(common.REPOS['rust'])  # required real genrule source, no guessed historical SHA
        inventories = {kind: common.source_inventory(repo, kind) for kind, repo in common.REPOS.items()}
        original_outputs = {'soong': common.footprint(common.OUT), 'dxvk': common.footprint(common.DXVK_BASE/'build-arm64')}
        before = {'repositoryStates': states, 'sources': inventories, 'dependencySources': dependency_inventory, 'dependencyStates': dependency_states, 'protected': protected, 'outputs': original_outputs}
        common.write_new(root/'before-c15.json', before)
        for name in ('source', 'upper', 'work', 'view', 'home', 'artifact'):
            (root/name).mkdir(mode=0o700)
        artifact = root/'artifact'
        print('C15: copying fresh private source/dependency trees', flush=True)
        for name, path in common.DEPENDENCIES.items():
            common.copy_source(path, root/'source'/name, dependency_inventory[name])
        for kind in ('virgl', 'dxvk'):
            common.copy_source(common.REPOS[kind], root/'source'/kind, inventories[kind])
        (root/'source/virglrenderer').symlink_to('virgl', target_is_directory=True)
        common.validate_dependency('virglrenderer', (root/'source/virglrenderer').resolve(strict=True), root/'source')
        common.copy_source(common.REPOS['rust'], root/'source/rust', inventories['rust'], root/'source')
        common.apply_payload(plan, stage, root/'source')
        common.verify_postimages(plan, root/'source')
        # Preserve the exact original Android relative .git symlink. In the
        # container it resolves into .repo under the existing readonly BASE;
        # a direct directory bind would change relative Git metadata paths.
        git_link = common.preserve_android_git_link(root/'source')
        common.write_new(artifact/'private-git-link-provenance.json', git_link)
        private = {kind: common.source_inventory(root/'source'/kind, kind, root/'source') for kind in common.REPOS}
        for name in common.DEPENDENCIES:
            private[name] = common.source_inventory(root/'source'/name, name)
            if private[name] != dependency_inventory[name]:
                raise RuntimeError('private dependency differs from original: '+name)
        common.write_new(artifact/'dependency-provenance.json', dep)
        common.write_new(artifact/'compiler-source-inputs.json', private)
        (artifact/'compiler-configs').mkdir()
        for name in ('prebuilt-intermediates/config.h', 'prebuilt-intermediates/config-server.h', 'Android.bp'):
            config = root/'source/virgl'/name
            if not config.is_file() or config.is_symlink():
                raise RuntimeError('actual compiler configuration missing: '+name)
            common.copy_new(config, artifact/'compiler-configs'/Path(name).name)
        common.write_new(artifact/'private-source-copy-policy.json', {'gitMetadata': 'Exact original Android .git symlink into inherited readonly BASE/.repo; no metadata copy/archive',
                         'absoluteInternalSymlinks': 'converted to equivalent relative links inside private repo',
                         'externalRustSymlinks': 'exact reviewed three only: minigbm/minijail private copies; virglrenderer private patched alias',
                         'excludedSecretsAndOldObjects': True, 'dxvkObjectsBorrowed': False})
        env = dict(os.environ)
        env['PATH'] = recipe['toolResolution']['PATHPrefix'] + os.pathsep + env.get('PATH', '')
        tools = {}
        for name in ('meson', 'ninja', 'patchelf'):
            resolved = shutil.which(name, path=env['PATH'])
            if not resolved:
                raise RuntimeError('required existing tool missing: ' + name)
            tools[name] = tool_identity(resolved)
            capture([resolved, '--version'], artifact/(name+'-version.txt'), env=env)
        glslang = shutil.which('glslang', path=env['PATH']) or shutil.which('glslangValidator', path=env['PATH'])
        if not glslang:
            raise RuntimeError('existing shader compiler missing; never install')
        tools['glslangPathCandidate'] = tool_identity(glslang)
        tools['python'] = tool_identity(sys.executable)
        common.write_new(artifact/'python-version.json', {'version': sys.version, 'executable': sys.executable})
        if (artifact/'meson-version.txt').read_text().strip() != recipe['toolResolution']['expectedMesonVersion']:
            raise RuntimeError('Meson version changed')
        if (artifact/'ninja-version.txt').read_text().strip() != recipe['toolResolution']['expectedNinjaVersion']:
            raise RuntimeError('Ninja version changed')
        llvm = common.NDK/'toolchains/llvm/prebuilt/linux-x86_64/bin'
        for name in ('aarch64-linux-android30-clang', 'aarch64-linux-android30-clang++', 'llvm-ar', 'llvm-strip', 'llvm-ranlib', 'llvm-readelf'):
            tools[name] = tool_identity(llvm/name, common.NDK)
        capture([str(llvm/'aarch64-linux-android30-clang++'), '--version'], artifact/'clang-version.txt')
        common.write_new(artifact/'tools.json', tools)
        # Assert old five again immediately before any compiler/setup action.
        common.verify_protected(plan)
        common.assert_owned(root, args.lease_owner)
        image = subprocess.check_output(['docker', 'image', 'inspect', '--format', '{{.Id}}', plan['buildImage']], text=True).strip()
        if image != plan['buildImage']:
            raise RuntimeError('reviewed image absent; never pull')
        inner = common.host_inner(plan)
        with (root/'host-inner.sh').open('x') as f: f.write(inner)
        command(['bash', '-n', str(root/'host-inner.sh')], artifact/'host-inner-syntax.log')
        host = common.host_command(root, plan['buildImage'])
        common.write_new(artifact/'host-command.json', {'argv': host, 'targets': plan['hostTargets']})
        command(['sudo', '-n', 'mount', '-t', 'overlay', 'overlay', '-o',
                 f'lowerdir={common.OUT},upperdir={root/"upper"},workdir={root/"work"},redirect_dir=on', str(root/'view')], artifact/'mount.log')
        mounted = True
        print('C15: starting reviewed three-target Android host build command', flush=True)
        command(host, artifact/'host-build.log')
        if common.sha(root/'view'/plan['nativeClient']['archiveRelative']) != plan['nativeClient']['archiveSha256']:
            raise RuntimeError('native display client changed')
        (artifact/'host').mkdir()
        host_files = []
        for target in plan['hostTargets']:
            binary = root/'view'/target.removeprefix('out/')
            checked_elf(binary)
            dest = artifact/'host'/binary.name
            common.copy_new(binary, dest)
            capture(['readelf', '-h', '-d', '-n', str(binary)], artifact/'host'/(binary.name+'.elf.txt'))
            host_files.append({'name': binary.name, 'path': str(dest.relative_to(artifact)), 'bytes': dest.stat().st_size, 'sha256': common.sha(dest)})
        common.write_new(artifact/'host-new-objects.json', object_manifest(root/'upper'))
        # Use only a brand-new Meson directory. No old coredata/ninja/object
        # paths were copied into the source tree, and there is no build yet.
        if (root/'dxvk-build').exists():
            raise RuntimeError('fresh DXVK build directory already exists')
        print('C15: starting fresh DXVK configure command', flush=True)
        common.verify_protected(plan)
        command(recipe['setupArgv'], artifact/'dxvk-setup.log', env=env)
        setup = verify_dxvk_setup(root/'dxvk-build', recipe)
        common.write_new(artifact/'dxvk-setup-verified.json', setup)
        common.copy_new(root/'dxvk-build/compile_commands.json', artifact/'dxvk-compile_commands.json')
        capture([tools['ninja']['resolved'], '-C', str(root/'dxvk-build'), '-t', 'commands'], artifact/'dxvk-ninja-commands.txt', env=env)
        print('C15: starting full matched-pair DXVK Ninja build command', flush=True)
        command(recipe['buildArgv'], artifact/'dxvk-build.log', env=env)
        capture([tools['ninja']['resolved'], '-C', str(root/'dxvk-build'), '-t', 'deps'], artifact/'dxvk-ninja-deps.txt', env=env)
        inputs = compiler_inputs(root/'dxvk-build', root/'source/dxvk',
                                 (artifact/'dxvk-ninja-deps.txt').read_text(), artifact/'generated-compiler-inputs')
        for entry in plan['files']['dxvk']:
            expected_path = str(root/'source/dxvk'/entry['path'])
            if not any(x['resolved'] == expected_path and x['sha256'] == entry['postSha256'] for x in inputs):
                raise RuntimeError('patched DXVK input absent from actual compiler dependency evidence: '+entry['path'])
        common.write_new(artifact/'dxvk-compiler-input-files.json', inputs)
        (artifact/'dxvk').mkdir()
        dxvk_files = []
        for item in recipe['postBuildPrivateOnly']:
            binary = Path(item['input'])
            checked_elf(binary)
            unstripped, packed = Path(item['copyUnstrippedTo']), Path(item['copyPackedTo'])
            common.copy_new(binary, unstripped)
            common.copy_new(binary, packed)
            command(item['stripArgv'], artifact/'dxvk'/(packed.name+'.strip.log'), env=env)
            command(item['rpathArgv'], artifact/'dxvk'/(packed.name+'.rpath.log'), env=env)
            capture(item['inspectArgv'], artifact/'dxvk'/(packed.name+'.elf.txt'), env=env)
            report = (artifact/'dxvk'/(packed.name+'.elf.txt')).read_text()
            if '$ORIGIN' not in report:
                raise RuntimeError('private matched DXVK RPATH differs')
            dxvk_files.append({'name': packed.name, 'path': str(packed.relative_to(artifact)), 'sha256': common.sha(packed),
                               'bytes': packed.stat().st_size, 'unstrippedSha256': common.sha(unstripped), 'unstrippedBytes': unstripped.stat().st_size})
        if {x['name'] for x in dxvk_files} != {'libdxvk_d3d11.so', 'libdxvk_dxgi.so'}:
            raise RuntimeError('new matched pair incomplete')
        common.write_new(artifact/'dxvk-all-new-objects.json', object_manifest(root/'dxvk-build'))
        shutil.copytree(root/'dxvk-build/meson-info', artifact/'dxvk-meson-info')
        shutil.copytree(root/'dxvk-build/meson-logs', artifact/'dxvk-meson-logs')
        for name in ('version.h', 'buildenv.h'):
            if (root/'dxvk-build'/name).is_file(): common.copy_new(root/'dxvk-build'/name, artifact/name)
        common.verify_postimages(plan, root/'source')
        after_private = {kind: common.source_inventory(root/'source'/kind, kind, root/'source') for kind in common.REPOS}
        for name in common.DEPENDENCIES:
            after_private[name] = common.source_inventory(root/'source'/name, name)
        common.validate_dependency('virglrenderer', (root/'source/virglrenderer').resolve(strict=True), root/'source')
        if after_private != private:
            raise RuntimeError('compiler source/dependency bytes changed during build')
        # Capture the exact compiler inputs, excluding Git/credentials and
        # old objects by the same source inventory used before compilation.
        print('C15: recording exact private compiler inputs and source archive', flush=True)
        with tarfile.open(artifact/'source-inputs.tar.gz', 'x:gz') as archive:
            def source_tar_metadata(info):
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                return info
            archive.add(root/'source/virglrenderer', arcname='source/virglrenderer', recursive=False, filter=source_tar_metadata)
            for kind, entries in private.items():
                for name in sorted(entries):
                    archive.add(root/'source'/kind/name, arcname='source/'+kind+'/'+name, recursive=False, filter=source_tar_metadata)
        for name in ('c15-build-plan.json', 'fresh-dxvk-recipe.json', 'android-aarch64.effective.txt', 'c15-build-approval.json', 'build-private-c15.py', 'c15_build_common.py'):
            common.copy_new(stage/name, artifact/name)
        common.write_new(artifact/'manifest.json', {'status': 'BUILT_FIVE_MATCHED_FILES_NOT_DEPLOYED_NOT_RUNTIME_TESTED',
                         'sourcePlanSha256': common.sha(stage/'c15-build-plan.json'), 'approvalSha256': args.approval_sha256,
                         'phase0PacketSha256': plan['phase0']['packetSha256'], 'host': host_files, 'dxvkMatchedPair': dxvk_files,
                         'runtimeSet': plan['runtimeSet'], 'nativeClientSha256': common.sha(root/'view'/plan['nativeClient']['archiveRelative']),
                         'objects': 'Host new/changed COW objects only; DXVK all objects from fresh private build. Unchanged Soong dependencies remain protected RO lower inputs.',
                         'sourceArchiveSha256': common.sha(artifact/'source-inputs.tar.gz'), 'runtimeFlagsEnabled': False,
                         'acceptanceRequires': ['c15-build-result.json success true', 'protected-after-c15.json all checks true',
                                                'cleanup-c15.json umountExit0 and ownMountStillPresent false']})
        success = True
    except Exception as exc:
        error = str(exc)
        print('C15: stopped; preserve private evidence: '+error, flush=True)
        raise
    finally:
        try:
            if before is not None:
                print('C15: verifying all original sources and outputs remained unchanged', flush=True)
                checks = {'originalRepositoriesUnchanged': {k: common.repo_state(p) for k,p in common.REPOS.items()} == before['repositoryStates'],
                          'originalDependencyGitStatesUnchanged': {name: common.repo_state(path) for name,path in common.DEPENDENCIES.items()} == before['dependencyStates'],
                          'originalDependenciesUnchanged': {name: common.source_inventory(path,name) for name,path in common.DEPENDENCIES.items()} == before['dependencySources'],
                          'originalSourceBytesUnchanged': {k: common.source_inventory(p,k) for k,p in common.REPOS.items()} == before['sources'],
                          'protectedOriginalsUnchanged': common.verify_protected(plan) == before['protected'],
                          'originalSoongOutUnchanged': common.footprint(common.OUT) == before['outputs']['soong'],
                          'originalDxvkBuildUnchanged': common.footprint(common.DXVK_BASE/'build-arm64') == before['outputs']['dxvk']}
                common.write_new(root/'protected-after-c15.json', checks)
                if not all(checks.values()):
                    success = False
                    error = 'Original preservation check failed; never auto-restore'
        except Exception as check_error:
            success = False
            error = 'Original preservation verification incomplete: '+str(check_error)
            if not (root/'protected-after-c15.json').exists():
                common.write_new(root/'protected-after-c15.json', {'verified': False, 'error': error})
        finally:
            if mounted:
                try:
                    unmount = subprocess.run(['sudo', '-n', 'umount', str(root/'view')]).returncode
                    present = any(line.split()[4] == str(root/'view') for line in Path('/proc/self/mountinfo').read_text().splitlines())
                    common.write_new(root/'cleanup-c15.json', {'umountExit': unmount, 'ownMountStillPresent': present, 'time': time.time()})
                    if unmount or present:
                        success = False
                        error = 'Own COW mount cleanup failed; coordinator must inspect'
                except Exception as cleanup_error:
                    success = False
                    error = 'Own COW cleanup verification incomplete: '+str(cleanup_error)
                    if not (root/'cleanup-c15.json').exists():
                        common.write_new(root/'cleanup-c15.json', {'verified': False, 'error': error})
            else:
                common.write_new(root/'cleanup-c15.json', {'mountCreated': False, 'time': time.time()})
            common.write_new(root/'c15-build-result.json', {'success': success, 'error': error, 'time': time.time(), 'buildOnly': True})
        if not success and error:
            raise RuntimeError(error)
    print('C15: private five-file build complete; retrieve and independently verify before coordinator releases lease/powers off', flush=True)

if __name__ == '__main__':
    main()
