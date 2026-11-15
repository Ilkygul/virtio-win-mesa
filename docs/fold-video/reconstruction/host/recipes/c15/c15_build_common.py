"""Private C15 build helpers. No work is performed at import time."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess

BASE = Path('/home/igul/droidvm-build-neptune')
TREE = BASE / 'crosvm_build'
OUT = TREE / 'out'
DXVK_BASE = Path('/home/igul/dxvk-android')
NDK = Path('/home/igul/droidvm-build/android-sdk/ndk/28.2.13676358')
REPOS = {'rust': TREE/'external/crosvm', 'virgl': TREE/'external/virglrenderer', 'dxvk': DXVK_BASE/'dxvk'}
DEPENDENCIES = {name: TREE/'external'/name for name in ('minigbm', 'minijail')}
RUST_EXTERNAL_LINKS = {'third_party/minigbm': ('minigbm', '../../minigbm/'),
                       'third_party/minijail': ('minijail', '../../minijail'),
                       'third_party/virglrenderer': ('virglrenderer', '../../virglrenderer')}
MAX_SOURCE_ENTRIES = 50000
MAX_SOURCE_FILE = 32 * 1024 * 1024
MAX_SOURCE_TOTAL = 1024 * 1024 * 1024
MAX_FOOTPRINT_ENTRIES = 200000
EXCLUDED_DIRS = {'.git', '.hg', '.svn', '.ssh', '.aws', '.gnupg', '__pycache__', 'out', 'build', 'builddir', 'build-arm64', 'meson-private', 'meson-logs', '.cache'}
EXCLUDED_SECRET = {'.env', '.envrc', '.netrc', '.npmrc', '.pypirc', '.git-credentials', 'credentials', 'credentials.json', 'credentials.toml', 'id_rsa', 'id_ed25519'}
EXCLUDED_EXT = {'.pfx', '.p12', '.pem', '.key'}
DXVK_OLD_OBJECTS = {'.o', '.obj', '.a', '.so', '.dll', '.exe', '.pch', '.gch', '.lib', '.dylib', '.rlib', '.bc'}
BUILD_IMAGE = 'sha256:c522b381183b9094b0b3596a7c97db160d90cc737998fb9fa17aa3a6fba71f55'
HOST_TARGETS = [
    'out/soong/.intermediates/external/crosvm/crosvm_device_only/crosvm_device_only_bin/android_arm64_armv8-a/crosvm',
    'out/soong/.intermediates/external/virglrenderer/libvirglrenderer/android_arm64_armv8-a_shared/libvirglrenderer.so',
    'out/soong/.intermediates/external/virglrenderer/virgl_render_server/android_arm64_armv8-a/virgl_render_server',
]
RUNTIME_SET = ['crosvm', 'libvirglrenderer.so', 'virgl_render_server', 'libdxvk_d3d11.so', 'libdxvk_dxgi.so']

def safe_relative(value):
    p = Path(value)
    if not p.parts or p.is_absolute() or '..' in p.parts or not re.fullmatch(r'[A-Za-z0-9_./+-]+', value):
        raise RuntimeError('invalid relative payload name')
    return p

def no_symlink(path):
    for item in reversed([Path(path), *Path(path).parents]):
        if item.is_symlink():
            raise RuntimeError('symlink path refused: ' + str(item))

def sha(path, cap=2 * 1024 * 1024 * 1024):
    path = Path(path)
    s = path.stat()
    if not stat.S_ISREG(s.st_mode) or s.st_size > cap:
        raise RuntimeError('not bounded regular file: ' + str(path))
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    after = path.stat()
    if (s.st_ino, s.st_size, s.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
        raise RuntimeError('file changed during hash: ' + str(path))
    return h.hexdigest()

def write_new(path, data):
    with Path(path).open('x') as f:
        json.dump(data, f, indent=2)
        f.write('\n')

def copy_new(source, dest):
    with Path(source).open('rb') as src, Path(dest).open('xb') as dst:
        shutil.copyfileobj(src, dst, 1024*1024)
    shutil.copystat(source, dest)

def git(repo, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    p = subprocess.run(['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-C', str(repo), *args],
                       capture_output=True, text=True, timeout=20, env=env)
    if p.returncode or len(p.stdout) > 2 * 1024 * 1024:
        raise RuntimeError('bounded git read failed: ' + args[0])
    return p.stdout.strip('\n')

def repo_state(repo):
    return {'head': git(repo, 'rev-parse', 'HEAD'),
            'status': git(repo, 'status', '--porcelain=v1', '--untracked-files=no')}

def dependency_targets(source_root=None):
    if source_root is None:
        return dict(DEPENDENCIES, virglrenderer=REPOS['virgl'])
    source_root = Path(source_root)
    no_symlink(source_root)
    return {name: source_root/name for name in ('minigbm', 'minijail', 'virglrenderer')}

def validate_dependency(name, target, source_root=None):
    expected = dependency_targets(source_root)[name]
    if source_root is not None and name == 'virglrenderer':
        if not expected.is_symlink() or os.readlink(expected) != 'virgl':
            raise RuntimeError('exact private patched-Virgl sibling alias required')
        no_symlink(Path(source_root)/'virgl')
        actual_expected = Path(source_root)/'virgl'
    else:
        no_symlink(expected)
        actual_expected = expected
    if target != actual_expected or not target.is_dir():
        raise RuntimeError('reviewed dependency target differs: ' + name)
    return expected

def rust_generated_inputs(repo):
    """Exact required Rust source directory, not a reusable build output."""
    directory = Path(repo)/'power_monitor/out'
    no_symlink(directory)
    if not directory.is_dir():
        raise RuntimeError('required power_monitor/out source directory absent')
    result, total = {}, 0
    with os.scandir(directory) as entries:
        for entry in entries:
            if len(result) >= 64:
                raise RuntimeError('power_monitor/out source count cap')
            item = entry.stat(follow_symlinks=False)
            if (not stat.S_ISREG(item.st_mode) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*\.rs', entry.name) or
                not 0 <= item.st_size <= 8*1024*1024):
                raise RuntimeError('power_monitor/out requires bounded regular Rust source files only')
            total += item.st_size
            if total > 16*1024*1024:
                raise RuntimeError('power_monitor/out source byte cap')
            source = directory/entry.name
            digest = sha(source, 8*1024*1024)
            with source.open('rb') as stream:
                raw = stream.read(8*1024*1024+1)
            if len(raw) != item.st_size or hashlib.sha256(raw).hexdigest() != digest or b'\0' in raw:
                raise RuntimeError('power_monitor/out requires stable text Rust sources')
            try:
                raw.decode('utf-8')
            except UnicodeDecodeError as exc:
                raise RuntimeError('power_monitor/out Rust source is not UTF-8 text') from exc
            name = 'power_monitor/out/'+entry.name
            result[name] = {'kind': 'file', 'bytes': item.st_size, 'mode': stat.S_IMODE(item.st_mode),
                            'sha256': digest}
    if not result:
        raise RuntimeError('power_monitor/out source inputs empty')
    return result

def source_inventory(repo, kind, dependency_root=None):
    repo = Path(repo)
    no_symlink(repo)
    result, total = {}, 0
    generated_path = repo/'power_monitor/out'
    generated = rust_generated_inputs(repo) if kind == 'rust' and (generated_path.exists() or generated_path.is_symlink()) else {}
    for directory, dirs, names in os.walk(repo, followlinks=False):
        parent = Path(directory)
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS or
                         (kind == 'rust' and d == 'out' and parent.relative_to(repo).as_posix() == 'power_monitor'))
        links = [d for d in dirs if (parent/d).is_symlink()]
        dirs[:] = [d for d in dirs if d not in links]
        for name in sorted(names + links):
            if name in EXCLUDED_SECRET or name.startswith('.env') or name == '.git' or Path(name).suffix.lower() in EXCLUDED_EXT:
                continue
            if kind == 'dxvk' and (Path(name).suffix.lower() in DXVK_OLD_OBJECTS or re.search(r'\.so(?:\.[0-9A-Za-z._-]+)?$', name) or name in ('build.ninja', 'coredata.dat', 'compile_commands.json')):
                continue
            p = parent/name
            rel = str(p.relative_to(repo))
            if len(result) >= MAX_SOURCE_ENTRIES:
                raise RuntimeError('source entry cap')
            if p.is_symlink():
                target = p.resolve(strict=True)
                if not target.is_relative_to(repo):
                    item = RUST_EXTERNAL_LINKS.get(rel)
                    if kind != 'rust' or item is None or os.readlink(p) != item[1]:
                        raise RuntimeError('external source symlink refused: ' + rel)
                    validate_dependency(item[0], target, dependency_root)
                    result[rel] = {'kind': 'dependency_symlink', 'link': item[1],
                                   'dependency': item[0], 'directory': True}
                    continue
                if kind in ('rust', 'virgl'):
                    documented = name == '.clang-format' or (kind == 'rust' and rel == 'rutabaga_gfx/src/generated/generate' and os.readlink(p) == 'generate.py')
                    if not documented:
                        raise RuntimeError('undocumented C12 source symlink: ' + rel)
                result[rel] = {'kind': 'symlink', 'link': os.readlink(p),
                               'target': str(target.relative_to(repo)), 'directory': target.is_dir()}
            else:
                s = p.stat()
                if not stat.S_ISREG(s.st_mode) or s.st_size > MAX_SOURCE_FILE:
                    raise RuntimeError('source not bounded regular file: ' + rel)
                total += s.st_size
                if total > MAX_SOURCE_TOTAL:
                    raise RuntimeError('source byte cap')
                result[rel] = {'kind': 'file', 'bytes': s.st_size, 'mode': stat.S_IMODE(s.st_mode),
                               'sha256': sha(p, MAX_SOURCE_FILE)}
    if generated:
        observed = {name: item for name,item in result.items() if name.startswith('power_monitor/out/')}
        if observed != generated:
            raise RuntimeError('power_monitor/out source set/bytes changed during inventory')
    return result

def copy_source(repo, dest, inventory, dependency_root=None):
    repo, dest = Path(repo), Path(dest)
    dest.mkdir(mode=0o700, exist_ok=False)
    for name, item in sorted(inventory.items()):
        p = dest/name
        p.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if item['kind'] == 'file':
            if p.exists() or p.is_symlink():
                raise RuntimeError('private destination exists')
            copy_new(repo/name, p)
            if sha(p, MAX_SOURCE_FILE) != item['sha256']:
                raise RuntimeError('private source copy differs')
    # Materialize links only after all real files have been copied. Absolute
    # internal source links become equivalent relative private links; none
    # can refer back to an original worktree or an external header directory.
    for name, item in sorted(inventory.items()):
        if item['kind'] == 'dependency_symlink':
            allowed = RUST_EXTERNAL_LINKS.get(name)
            if (allowed is None or item.get('dependency') != allowed[0] or
                item.get('link') != allowed[1] or dependency_root != dest.parent):
                raise RuntimeError('unreviewed private dependency link')
            expected = dependency_targets(dependency_root)[allowed[0]]
            validate_dependency(allowed[0], expected.resolve(strict=True), dependency_root)
            p = dest/name
            p.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            p.symlink_to(allowed[1], target_is_directory=True)
            if p.resolve(strict=True) != expected.resolve(strict=True):
                raise RuntimeError('private dependency link differs')
            continue
        if item['kind'] != 'symlink':
            continue
        p = dest/name
        p.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        target = dest/item['target']
        if item['directory']:
            target.mkdir(mode=0o700, parents=True, exist_ok=True)
        p.symlink_to(os.path.relpath(target, p.parent), target_is_directory=item['directory'])
    for name, item in inventory.items():
        if item['kind'] == 'symlink' and not (dest/name).resolve(strict=True).is_relative_to(dest):
            raise RuntimeError('private source link escapes')

def preserve_android_git_link(source_root):
    source_root = Path(source_root)
    no_symlink(source_root/'rust')
    original = REPOS['rust']/'.git'
    raw = '../../.repo/projects/external/crosvm.git'
    target = TREE/'.repo/projects/external/crosvm.git'
    no_symlink(target)
    if (not original.is_symlink() or os.readlink(original) != raw or
        original.resolve(strict=True) != target or not target.is_dir()):
        raise RuntimeError('exact original Android Rust Git metadata link required')
    private = source_root/'rust/.git'
    if private.exists() or private.is_symlink():
        raise RuntimeError('fresh private Git metadata link required')
    private.symlink_to(raw, target_is_directory=True)
    return {'rawLink': raw, 'originalTarget': str(target),
            'containerTarget': '/work/crosvm_build/.repo/projects/external/crosvm.git',
            'access': 'Inherited original BASE readonly bind; no Git metadata copied or archived'}

def footprint(root):
    root = Path(root)
    result = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        parent = Path(directory)
        links = [d for d in dirs if (parent/d).is_symlink()]
        dirs[:] = [d for d in dirs if d not in links]
        for name in sorted(names + links):
            p = parent/name
            if len(result) >= MAX_FOOTPRINT_ENTRIES:
                raise RuntimeError('original output footprint cap')
            if p.is_symlink():
                result[str(p.relative_to(root))] = {'symlink': os.readlink(p)}
            elif p.is_file():
                s = p.stat()
                result[str(p.relative_to(root))] = [s.st_size, s.st_mtime_ns]
            else:
                # The existing Android out has these exact Ninja status FIFO and path logger socket.
                # Stat only: never open/read it or alter the protected lower tree or communicate with the socket.
                info = p.lstat()
                rel = str(p.relative_to(root))
                fifo = root == OUT and rel == '.ninja_fifo' and stat.S_ISFIFO(info.st_mode)
                sock = root == OUT and rel == '.path_interposer_log' and stat.S_ISSOCK(info.st_mode)
                if not (fifo or sock):
                    raise RuntimeError('unexpected output filesystem object')
                result[rel] = {'kind': 'fifo' if fifo else 'socket', 'mode': info.st_mode,
                               'uid': info.st_uid, 'gid': info.st_gid,
                               'inode': info.st_ino, 'size': info.st_size,
                               'mtime_ns': info.st_mtime_ns, 'ctime_ns': info.st_ctime_ns,
                               'rdev': info.st_rdev}
    return result

def all_protected(plan):
    data = dict(plan['additionalProtectedOriginals'])
    data.update({x['path']: x['sha256'] for x in plan['protectedArtifacts']})
    return data

def verify_protected(plan):
    result = {}
    if len(plan['protectedArtifacts']) != 5:
        raise RuntimeError('five actual baseline artifacts required')
    for name, expected in all_protected(plan).items():
        no_symlink(Path(name))
        actual = sha(name, 64 * 1024 * 1024)
        if actual != expected:
            raise RuntimeError('protected original hash mismatch: ' + name)
        result[name] = actual
    return result

def assert_owned(root, owner):
    no_symlink(root)
    s = root.stat()
    if root != Path('/home/igul/codex-c15-host-r7') or s.st_uid != os.getuid() or s.st_mode & 0o077:
        raise RuntimeError('expected owned0700 phase0 root required')
    lock = Path('/home/igul/.cache/bouw-lock.d')
    if not re.fullmatch(r'codex-[a-z0-9-]+', owner) or lock.joinpath('owner').read_text().split()[0] != owner:
        raise RuntimeError('explicit own lease required')

def verify_live_inputs(plan, stage):
    result = {}
    for kind, repo in REPOS.items():
        s = repo_state(repo)
        lines = s['status'].splitlines()
        if s['head'] != plan['heads'][kind] or any(x[:2] != ' M' for x in lines) or sorted(x[3:] for x in lines) != sorted(plan['expectedTrackedDirty'][kind]):
            raise RuntimeError('original repository HEAD/status mismatch: ' + kind)
        result[kind] = s
        for f in plan['files'][kind]:
            rel = safe_relative(f['path'])
            live = repo/rel
            if f['liveSha256'] is None:
                if live.exists() or live.is_symlink():
                    raise RuntimeError('ADD baseline exists: ' + str(live))
            else:
                no_symlink(live)
                if sha(live, MAX_SOURCE_FILE) != f['liveSha256']:
                    raise RuntimeError('live source baseline mismatch: ' + str(live))
            proposed = stage/'payload'/kind/rel
            no_symlink(proposed)
            if sha(proposed, MAX_SOURCE_FILE) != f['postSha256']:
                raise RuntimeError('staged postimage mismatch: ' + str(rel))
    for name, expected in plan['dxvkExtraLeases'].items():
        if sha(REPOS['dxvk']/safe_relative(name), MAX_SOURCE_FILE) != expected:
            raise RuntimeError('e105 extra overlay mismatch')
    for item in plan['originalMetadata']:
        no_symlink(Path(item['path']))
        if sha(item['path'], 2 * 1024 * 1024) != item['sha256']:
            raise RuntimeError('original phase0 metadata changed: ' + item['path'])
    for name, expected in plan['compilerConfigBaselines'].items():
        p = REPOS['virgl']/safe_relative(name)
        no_symlink(p)
        if sha(p, MAX_SOURCE_FILE) != expected:
            raise RuntimeError('actual C12 compiler configuration changed: '+name)
    return result

def apply_payload(plan, stage, source_root):
    for kind, entries in plan['files'].items():
        for entry in entries:
            rel = safe_relative(entry['path'])
            dest = source_root/kind/rel
            if entry['liveSha256'] is None:
                if dest.exists() or dest.is_symlink():
                    raise RuntimeError('private ADD unexpectedly exists')
            elif sha(dest, MAX_SOURCE_FILE) != entry['liveSha256']:
                raise RuntimeError('private baseline differs')
            dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            shutil.copy2(stage/'payload'/kind/rel, dest)
            os.utime(dest, None)
            if sha(dest, MAX_SOURCE_FILE) != entry['postSha256']:
                raise RuntimeError('private final postimage differs')

def verify_postimages(plan, source_root):
    for kind, entries in plan['files'].items():
        for entry in entries:
            if sha(source_root/kind/safe_relative(entry['path']), MAX_SOURCE_FILE) != entry['postSha256']:
                raise RuntimeError('compiler-visible source changed')

def host_command(root, image):
    args = ['docker', 'run', '--rm', '--pull=never', '--name', 'codex-c15-private-host-r5',
            '--user', f'{os.getuid()}:{os.getgid()}', '-v', '/etc/passwd:/etc/passwd:ro', '-v', '/etc/group:/etc/group:ro',
            '-v', f'{BASE}:/work:ro', '-v', f'{root/"source/rust"}:/work/crosvm_build/external/crosvm:ro',
            '-v', f'{root/"source/virgl"}:/work/crosvm_build/external/virglrenderer:ro',
            '-v', f'{root/"source/minigbm"}:/work/crosvm_build/external/minigbm:ro',
            '-v', f'{root/"source/minijail"}:/work/crosvm_build/external/minijail:ro',
            '-v', f'{root/"view"}:/work/crosvm_build/out:rw', '-v', f'{root/"home"}:/home/codexbuild:rw',
            '-v', f'{root/"host-inner.sh"}:/codex-build.sh:ro', '-e', 'HOME=/home/codexbuild',
            '-w', '/work/crosvm_build', image, 'bash', '/codex-build.sh']
    return args

def host_inner(plan):
    if plan['hostTargets'] != HOST_TARGETS:
        raise RuntimeError('unexpected host targets')
    text = 'set -eo pipefail\ncd /work/crosvm_build\nsource build/envsetup.sh\nlunch aosp_arm64 trunk_staging eng\n'
    for kind, virtual in [('rust', 'external/crosvm'), ('virgl', 'external/virglrenderer')]:
        for f in plan['files'][kind]:
            safe_relative(f['path'])
            if not re.fullmatch(r'[0-9a-f]{64}', f['postSha256']):
                raise RuntimeError('invalid source postimage digest')
            text += "printf '%s  %s\\n' '"+f['postSha256']+"' '"+virtual+'/'+f['path']+"' | sha256sum -c -\n"
    return text+'NINJA_ARGS="-k 0" ALLOW_MISSING_DEPENDENCIES=true TARGET_BUILD_UNBUNDLED=true m '+' '.join(HOST_TARGETS)+' -j8\n'
