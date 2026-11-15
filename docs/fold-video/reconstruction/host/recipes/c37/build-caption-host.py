#!/usr/bin/env python3
"""Private two-target caption diagnostic build; no wake/VM/deploy/power actions.

Uses the unchanged proven C15 R8 source/protection helpers and actual C15
private compiler source as the baseline. Only the new private virgl copy is
patched. Existing support sources, BASE and lower out remain read-only.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
sys.dont_write_bytecode = True
import c15_build_common as c

ROOT = Path('/home/igul/codex-gpu-poll-c37-host-r1')
NAME = 'codex-gpu-poll-c37-host-r1'
OLD = Path('/home/igul/codex-c15-host-r7')
TARGETS = c.HOST_TARGETS[1:]

def owned(root, owner):
    c.no_symlink(root)
    s = root.stat()
    if root != ROOT or not stat.S_ISDIR(s.st_mode) or s.st_uid != os.getuid() or s.st_mode & 0o077:
        raise RuntimeError('exact fresh caller-owned0700 root required')
    if not re.fullmatch(r'codex-[a-z0-9-]+', owner):
        raise RuntimeError('explicit owned lease required')
    if Path('/home/igul/.cache/bouw-lock.d/owner').read_text().split()[0] != owner:
        raise RuntimeError('own build lease missing')

def command(argv, log):
    with log.open('x') as out:
        result = subprocess.run(argv, stdout=out, stderr=subprocess.STDOUT)
    c.write_new(log.with_suffix(log.suffix + '.result.json'), {'argv': argv, 'exit': result.returncode})
    if result.returncode:
        raise RuntimeError('command failed; preserve ' + str(log))

def private_inputs(root):
    return {kind: c.source_inventory(root / kind, kind, root)
            for kind in ['rust', 'virgl', 'dxvk', 'minigbm', 'minijail']}

def original_inputs():
    return {
        'repositoryStates': {k: c.repo_state(p) for k, p in c.REPOS.items()},
        'sources': {k: c.source_inventory(p, k) for k, p in c.REPOS.items()},
        'dependencyStates': {k: c.repo_state(p) for k, p in c.DEPENDENCIES.items()},
        'dependencySources': {k: c.source_inventory(p, k) for k, p in c.DEPENDENCIES.items()},
    }

def outputs():
    return {'soong': c.footprint(c.OUT), 'dxvk': c.footprint(c.DXVK_BASE / 'build-arm64')}

def objects(directory):
    result = []
    for parent, dirs, files in os.walk(directory, followlinks=False):
        if any((Path(parent) / n).is_symlink() for n in dirs):
            raise RuntimeError('unexpected object directory symlink')
        for name in files:
            p = Path(parent) / name
            if p.suffix not in {'.o', '.obj', '.a', '.rlib', '.pch', '.gch'}:
                continue
            c.no_symlink(p)
            result.append({'path': str(p.relative_to(directory)), 'bytes': p.stat().st_size, 'sha256': c.sha(p)})
    return result

def checked_elf(p):
    b = p.read_bytes()[:20]
    if b[:7] != b'\x7fELF\x02\x01\x01' or struct.unpack_from('<H', b, 18)[0] != 183:
        raise RuntimeError('expected ELF64 little-endian AArch64 output')

def host_inner():
    # Same C15 envsetup/lunch/flags/jobs. Only the explicit target set shrinks.
    return ('set -eo pipefail\ncd /work/crosvm_build\nsource build/envsetup.sh\n'
            'lunch aosp_arm64 trunk_staging eng\n'
            'sha256sum -c /codex-virgl-inputs.sha256\n'
            'NINJA_ARGS="-k 0" ALLOW_MISSING_DEPENDENCIES=true TARGET_BUILD_UNBUNDLED=true m ' +
            ' '.join(TARGETS) + ' -j8\n')

def host_command(root, image):
    return [
        'docker', 'run', '--rm', '--pull=never', '--name', NAME, '--user', f'{os.getuid()}:{os.getgid()}',
        '-v', '/etc/passwd:/etc/passwd:ro', '-v', '/etc/group:/etc/group:ro',
        '-v', f'{c.BASE}:/work:ro',
        '-v', f'{OLD/"source/rust"}:/work/crosvm_build/external/crosvm:ro',
        '-v', f'{root/"source/virgl"}:/work/crosvm_build/external/virglrenderer:ro',
        '-v', f'{OLD/"source/minigbm"}:/work/crosvm_build/external/minigbm:ro',
        '-v', f'{OLD/"source/minijail"}:/work/crosvm_build/external/minijail:ro',
        '-v', f'{root/"view"}:/work/crosvm_build/out:rw',
        '-v', f'{root/"home"}:/home/codexbuild:rw',
        '-v', f'{root/"host-inner.sh"}:/codex-build.sh:ro',
        '-v', f'{root/"virgl-inputs.sha256"}:/codex-virgl-inputs.sha256:ro',
        '-e', 'HOME=/home/codexbuild', '-w', '/work/crosvm_build', image, 'bash', '/codex-build.sh',
    ]

def container_running():
    result = subprocess.run(['docker', 'ps', '-q', '--filter', 'name=^/' + NAME + '$'],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('cannot prove private container stopped')
    return bool(result.stdout.strip())

def package(root, artifact):
    entries = []
    for p in sorted(artifact.rglob('*')):
        if p.is_dir():
            continue
        c.no_symlink(p)
        if p.suffix.lower() in c.EXCLUDED_EXT or '.git' in p.relative_to(artifact).parts:
            raise RuntimeError('forbidden retrieval member')
        entries.append({'path': str(p.relative_to(artifact)), 'bytes': p.stat().st_size, 'sha256': c.sha(p)})
    c.write_new(artifact / 'retrieval-manifest.json', {'status': 'BUILT_OR_FAILURE_EVIDENCE_NOT_DEPLOYED', 'files': entries})
    path = root / 'retrieval.tar.gz'
    with tarfile.open(path, 'x:gz') as tar:
        for entry in entries:
            tar.add(artifact / entry['path'], arcname=entry['path'], recursive=False)
        tar.add(artifact / 'retrieval-manifest.json', arcname='retrieval-manifest.json', recursive=False)
    c.write_new(root / 'retrieval-transport.json', {'path': str(path), 'bytes': path.stat().st_size, 'sha256': c.sha(path)})

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, required=True)
    ap.add_argument('--lease-owner', required=True)
    ap.add_argument('--packet-sha256', required=True)
    args = ap.parse_args()
    owned(args.root, args.lease_owner)
    stage = args.root / 'stage-caption-r1'
    c.no_symlink(stage)
    s = stage.stat()
    if s.st_uid != os.getuid() or s.st_mode & 0o077:
        raise RuntimeError('owned0700 stage required')
    manifest = stage / 'packet-manifest.json'
    if c.sha(manifest) != args.packet_sha256.lower():
        raise RuntimeError('explicit approved packet hash differs')
    packet = json.loads(manifest.read_text())
    for e in packet['files']:
        rel = c.safe_relative(e['path'])
        p = stage / rel
        c.no_symlink(p)
        if c.sha(p) != e['sha256'] or p.stat().st_size != e['bytes']:
            raise RuntimeError('staged packet differs: ' + str(rel))
    plan = json.loads((stage / 'build-plan.json').read_text())
    if plan['privateRoot'] != str(ROOT) or plan['hostTargets'] != TARGETS or plan['buildImage'] != c.BUILD_IMAGE:
        raise RuntimeError('fixed scope/root/image/targets differs')
    if c.sha(stage / 'c15_build_common.py') != plan['helperSha256']:
        raise RuntimeError('actual C15 helper changed')
    if c.sha(stage / 'source-inputs.tar.gz') != plan['sourceArchive']['sha256']:
        raise RuntimeError('actual C15 source archive differs')
    if c.sha(stage / 'baseline-private-inventory.json') != plan['baselinePrivateInventorySha256']:
        raise RuntimeError('baseline private inventory changed')
    if c.sha(stage / 'baseline-original-inputs.json') != plan['baselineOriginalInputsSha256']:
        raise RuntimeError('baseline original inventory changed')
    for n in ['source', 'upper', 'work', 'view', 'home', 'artifact', 'host-inner.sh', 'virgl-inputs.sha256',
              'retrieval.tar.gz', 'retrieval-transport.json']:
        if (args.root / n).exists() or (args.root / n).is_symlink():
            raise RuntimeError('fresh-only path exists: ' + n)
    artifact = args.root / 'artifact'
    artifact.mkdir(mode=0o700)
    success = False
    error = None
    mounted = False
    before = None
    private = None
    try:
        state = subprocess.check_output(['/home/igul/winbuild/vm.sh', 'status'], text=True).strip()
        if state != 'uit':
            raise RuntimeError('Windows build VM must remain off')
        expected_original = json.loads((stage / 'baseline-original-inputs.json').read_text())
        baseline = json.loads((stage / 'baseline-private-inventory.json').read_text())
        live = original_inputs()
        if live != expected_original:
            raise RuntimeError('original source/dependency HEAD/status/bytes changed')
        if private_inputs(OLD / 'source') != baseline:
            raise RuntimeError('actual C15 private support source differs from compiled archive')
        protected = c.verify_protected(plan)
        before = {'original': live, 'protected': protected, 'outputs': outputs(), 'oldPrivateSource': baseline}
        c.write_new(artifact / 'before.json', before)
        for name in ['source', 'upper', 'work', 'view', 'home']:
            (args.root / name).mkdir(mode=0o700)
        c.copy_source(OLD / 'source/virgl', args.root / 'source/virgl', baseline['virgl'])
        virgl = args.root / 'source/virgl'
        for e in plan['files']:
            rel = c.safe_relative(e['path'])
            f = virgl / rel
            if c.sha(f) != e['baselineSha256'] or c.sha(stage / 'payload' / rel) != e['postSha256']:
                raise RuntimeError('trace baseline/post mismatch: ' + str(rel))
            shutil.copyfile(stage / 'payload' / rel, f)
            os.utime(f, None)
            if c.sha(f) != e['postSha256']:
                raise RuntimeError('private trace post mismatch')
        private = c.source_inventory(virgl, 'virgl')
        expected = json.loads(json.dumps(baseline['virgl']))
        for e in plan['files']:
            expected[e['path']]['sha256'] = e['postSha256']
            expected[e['path']]['bytes'] = e['postBytes']
        if private != expected:
            raise RuntimeError('only exact five trace postimages may change')
        c.write_new(artifact / 'compiler-source-inputs.json', {'virgl': private, 'readOnlySupportC15': baseline,
                     'supportSourceArchiveSha256': plan['sourceArchive']['sha256']})
        (artifact / 'compiler-configs').mkdir()
        for n, expected_sha in plan['compilerConfigBaselines'].items():
            if c.sha(virgl / n) != expected_sha:
                raise RuntimeError('C15 actual compiler configuration changed')
            c.copy_new(virgl / n, artifact / 'compiler-configs' / Path(n).name)
        with (args.root / 'virgl-inputs.sha256').open('x') as out:
            for n, e in private.items():
                if e['kind'] == 'file':
                    out.write(e['sha256'] + '  external/virglrenderer/' + n + '\n')
        with (args.root / 'host-inner.sh').open('x') as out:
            out.write(host_inner())
        command(['bash', '-n', str(args.root / 'host-inner.sh')], artifact / 'inner-syntax.log')
        image = subprocess.check_output(['docker', 'image', 'inspect', '--format', '{{.Id}}', c.BUILD_IMAGE], text=True).strip()
        if image != c.BUILD_IMAGE:
            raise RuntimeError('existing exact image unavailable; never pull')
        readelf = Path(shutil.which('readelf') or '')
        if not readelf.is_file():
            raise RuntimeError('existing readelf unavailable; never install')
        c.write_new(artifact / 'tool-provenance.json', {'image': image,
                     'readelfResolved': str(readelf.resolve()), 'readelfSha256': c.sha(readelf.resolve()),
                     'recipe': 'Actual C15 envsetup/lunch/flags/-j8; two existing virgl targets only'})
        command([str(readelf), '--version'], artifact / 'readelf-version.log')
        owned(args.root, args.lease_owner)
        if c.verify_protected(plan) != protected:
            raise RuntimeError('old outputs changed before compiler')
        host = host_command(args.root, c.BUILD_IMAGE)
        c.write_new(artifact / 'host-command.json', {'argv': host, 'targets': TARGETS})
        command(['sudo', '-n', 'mount', '-t', 'overlay', 'overlay', '-o',
                 f'lowerdir={c.OUT},upperdir={args.root/"upper"},workdir={args.root/"work"},redirect_dir=on',
                 str(args.root / 'view')], artifact / 'mount.log')
        mounted = True
        print('ACTUAL_TWO_TARGET_CAPTION_BUILD_START', flush=True)
        command(host, artifact / 'host-build.log')
        client = plan['nativeClient']
        if c.sha(args.root / 'view' / client['archiveRelative']) != client['archiveSha256']:
            raise RuntimeError('unchanged native display client archive differs')
        hostdir = artifact / 'host'
        hostdir.mkdir()
        files = []
        for target in TARGETS:
            f = args.root / 'view' / target.removeprefix('out/')
            checked_elf(f)
            dest = hostdir / f.name
            c.copy_new(f, dest)
            command([str(readelf), '-h', '-d', '-n', str(f)], hostdir / (f.name + '.elf.txt'))
            files.append({'name': f.name, 'bytes': dest.stat().st_size, 'sha256': c.sha(dest)})
        c.write_new(artifact / 'new-cow-objects.json', objects(args.root / 'upper'))
        with tarfile.open(artifact / 'source-inputs.tar.gz', 'x:gz') as ar:
            for n in private:
                ar.add(virgl / n, arcname='source/virgl/' + n, recursive=False)
        c.copy_new(args.root / 'host-inner.sh', artifact / 'host-inner.sh')
        c.copy_new(args.root / 'virgl-inputs.sha256', artifact / 'virgl-inputs.sha256')
        c.write_new(artifact / 'artifacts.json', {'status': 'BUILT_NOT_DEPLOYED_DIAGNOSTIC_ONLY',
                     'files': files, 'unmodifiedRuntime': plan['unchangedRuntimeFiles'],
                     'flagsEnabledByBuild': False, 'captionOrPerformanceFixClaim': False})
        success = True
    except Exception as exc:
        error = str(exc)
    finally:
        cleanup = {'ownMountUnmounted': not mounted, 'containerStopped': False}
        try:
            if container_running():
                raise RuntimeError('private container still running; retain mount/owner; no forced cleanup')
            cleanup['containerStopped'] = True
            if mounted:
                command(['sudo', '-n', 'umount', str(args.root / 'view')], artifact / 'unmount.log')
                mounted = False
                cleanup['ownMountUnmounted'] = True
            if before is not None:
                checks = {'originalSourcesUnchanged': original_inputs() == before['original'],
                          'oldPrivateC15SourcesUnchanged': private_inputs(OLD / 'source') == before['oldPrivateSource'],
                          'oldArtifactsUnchanged': c.verify_protected(plan) == before['protected'],
                          'originalOutputsUnchanged': outputs() == before['outputs']}
                if private is not None:
                    checks['newCompilerSourceUnchanged'] = c.source_inventory(args.root / 'source/virgl', 'virgl') == private
                c.write_new(artifact / 'protection-after.json', checks)
                if not all(checks.values()):
                    raise RuntimeError('preservation verification failed')
        except Exception as exc:
            success = False
            error = (error + '; ' if error else '') + 'cleanup/protection: ' + str(exc)
        c.write_new(artifact / 'cleanup.json', cleanup)
        for e in packet['files']:
            dest = artifact / 'reviewed-packet' / e['path']
            dest.parent.mkdir(parents=True, exist_ok=True)
            c.copy_new(stage / e['path'], dest)
        c.copy_new(manifest, artifact / 'reviewed-packet/packet-manifest.json')
        c.write_new(artifact / 'build-result.json', {'success': success, 'error': error,
                     'packetSha256': args.packet_sha256, 'targets': TARGETS,
                     'noRuntimeOrDeviceActions': True, 'provenanceLimit': plan['provenanceLimit']})
        package(args.root, artifact)
    print((args.root / 'retrieval-transport.json').read_text(), flush=True)
    if not success:
        raise SystemExit('BUILD_FAILED_PRESERVED: ' + str(error))

if __name__ == '__main__':
    main()
