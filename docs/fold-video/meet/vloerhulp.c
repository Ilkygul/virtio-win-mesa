// vloerhulp: GPU floor + per-thread CPU uclamp for the Windows VM, driven by crosvm r8's activity signal.
// Since 18-11-2026 the maintained copy lives in termux-x11 droidvm/ksu-module-src (KernelSU module fold-vm, bin/vloerhulp).
// crosvm touches /data/adb/fold-vm/npt/sein (3 frames within 100 ms, at most every 100 ms). We wait on it with
// inotify (no polling of crosvm), boost within a few ms, hold 2 s after the last touch, then drop back.
//   boost: kgsl min_clock_mhz = BOOST_GPU; uclamp.min = UCLAMP on every thread of crosvm and its
//          virgl_render_server children (2b). If the kernel has no uclamp, or npt/uclamp-uit exists:
//          policy0/policy6 scaling_min_freq floors instead (only while boosted).
//   rest : min_clock_mhz = 422, uclamp.min 0, cluster floors from gpu-vloer.orig.
// Once per second: re-apply the floor if the phone reset it; when crosvm is gone or no panel is lit, restore
// everything and idle. npt/boost-signaal-uit: vloerhulp exits (gpu-vloer.sh v3 takes over again).
// Log: /data/adb/fold-vm/vloerhulp.log (one line per state change is too much; counters every 10 min).
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>

#define HERE "/data/adb/fold-vm"
#define NPT HERE "/npt"
#define K "/sys/class/kgsl/kgsl-3d0"
#define C "/sys/devices/system/cpu/cpufreq"
static int BOOST_GPU = 902, BASE_GPU = 422, HOLD_MS = 2000, UCLAMP = 512;
static char cpu0_boost[16] = "1804800", cpu6_boost[16] = "2496000", cpu0_orig[16] = "787200", cpu6_orig[16] = "883200";
static FILE *lg;

static void logf_(const char *f, ...) {
    if (!lg) return;
    time_t t = time(0); char b[32]; strftime(b, sizeof b, "%F %T", localtime(&t));
    va_list a; va_start(a, f); fprintf(lg, "%s ", b); vfprintf(lg, f, a); fputc('\n', lg); va_end(a); fflush(lg);
}
static int64_t ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000LL + t.tv_nsec / 1000000; }
static int exists(const char *p) { struct stat s; return stat(p, &s) == 0; }
static int rd(const char *p, char *b, int n) { int fd = open(p, O_RDONLY); if (fd < 0) return -1; int r = read(fd, b, n - 1); close(fd); if (r < 0) r = 0; b[r] = 0; char *e = strchr(b, '\n'); if (e) *e = 0; return r; }
static void put(const char *p, const char *v) { char b[32]; if (rd(p, b, sizeof b) >= 0 && !strcmp(b, v)) return; int fd = open(p, O_WRONLY); if (fd < 0) return; write(fd, v, strlen(v)); close(fd); }
static void puti(const char *p, int v) { char b[16]; snprintf(b, sizeof b, "%d", v); put(p, b); }

static int pname(const char *pid, char *out, int n);
struct sched_attr { uint32_t size, policy; uint64_t flags; int32_t nice; uint32_t prio; uint64_t rt, dl, per; uint32_t umin, umax; };
#define SCHED_FLAG_KEEP_POLICY 0x08
#define SCHED_FLAG_KEEP_PARAMS 0x10
#define SCHED_FLAG_UTIL_CLAMP_MIN 0x20
static int uclamp_ok = 1;
static int set_uclamp(pid_t tid, int v) {
    struct sched_attr a; memset(&a, 0, sizeof a); a.size = sizeof a; a.umin = v; a.umax = 1024;
    a.flags = SCHED_FLAG_KEEP_POLICY | SCHED_FLAG_KEEP_PARAMS | SCHED_FLAG_UTIL_CLAMP_MIN;
    return syscall(SYS_sched_setattr, tid, &a, 0);
}
// every thread of crosvm processes and their virgl_render_server children
static int vm_threads(int v) {
    DIR *d = opendir("/proc"); if (!d) return 0; struct dirent *e; int n = 0; char p[64], b[64];
    while ((e = readdir(d))) {
        if (e->d_name[0] < '0' || e->d_name[0] > '9') continue;
        if (pname(e->d_name, b, sizeof b) < 0) continue;
        if (strcmp(b, "crosvm") && strcmp(b, "virgl_render_server")) continue;
        snprintf(p, sizeof p, "/proc/%s/task", e->d_name); DIR *t = opendir(p); if (!t) continue; struct dirent *f;
        while ((f = readdir(t))) { if (f->d_name[0] < '0' || f->d_name[0] > '9') continue;
            if (set_uclamp(atoi(f->d_name), v) == 0) n++; else if (errno == EINVAL || errno == ENOSYS) uclamp_ok = 0; }
        closedir(t);
    }
    closedir(d); return n;
}
static int vm_alive(void) {
    DIR *d = opendir("/proc"); if (!d) return 0; struct dirent *e; char b[64]; int ok = 0;
    while (!ok && (e = readdir(d))) { if (e->d_name[0] < '0' || e->d_name[0] > '9') continue;
        if (pname(e->d_name, b, sizeof b) == 0 && !strcmp(b, "crosvm")) ok = 1; }
    closedir(d); return ok;
}
static int lit(void) {
    DIR *d = opendir("/sys/class/backlight"); if (!d) return 1; struct dirent *e; char p[160], b[16]; int on = 0;
    while ((e = readdir(d))) { if (strncmp(e->d_name, "panel", 5)) continue;
        snprintf(p, sizeof p, "/sys/class/backlight/%s/brightness", e->d_name); if (rd(p, b, sizeof b) > 0 && atoi(b) > 0) on = 1; }
    closedir(d); return on;
}
// process name from argv[0] (crosvm renames its main thread, so /proc/<pid>/comm says "Windows 11 ARM6")
static int pname(const char *pid, char *out, int n) {
    char p[64], b[256]; snprintf(p, sizeof p, "/proc/%s/cmdline", pid);
    if (rd(p, b, sizeof b) <= 0) return -1;
    const char *s = strrchr(b, '/'); s = s ? s + 1 : b; snprintf(out, n, "%s", s); return 0;
}
static int use_uclamp(void) { return uclamp_ok && !exists(NPT "/uclamp-uit"); }
enum { UIT, BASIS, BOOST };
static int state = UIT;
static void apply(int s) {
    if (s == BOOST) {
        puti(K "/min_clock_mhz", BOOST_GPU);
        if (use_uclamp()) { vm_threads(UCLAMP); put(C "/policy0/scaling_min_freq", cpu0_orig); put(C "/policy6/scaling_min_freq", cpu6_orig); }
        if (!use_uclamp()) { put(C "/policy0/scaling_min_freq", cpu0_boost); put(C "/policy6/scaling_min_freq", cpu6_boost); }
    } else {
        puti(K "/min_clock_mhz", BASE_GPU);
        if (state == BOOST || s == UIT) vm_threads(0);
        put(C "/policy0/scaling_min_freq", cpu0_orig); put(C "/policy6/scaling_min_freq", cpu6_orig);
    }
    state = s;
}
int main(int argc, char **argv) {
    char b[64];
    if (getenv("BOOST_GPU")) BOOST_GPU = atoi(getenv("BOOST_GPU"));
    if (getenv("HOLD_MS")) HOLD_MS = atoi(getenv("HOLD_MS"));
    if (getenv("UCLAMP")) UCLAMP = atoi(getenv("UCLAMP"));
    FILE *o = fopen(HERE "/gpu-vloer.orig", "r");
    if (o) { char l[3][32]; for (int i = 0; i < 3 && fgets(l[i], 32, o); i++) { l[i][strcspn(l[i], "\n")] = 0; if (i == 0) BASE_GPU = atoi(l[0]); if (i == 1) strcpy(cpu0_orig, l[1]); if (i == 2) strcpy(cpu6_orig, l[2]); } fclose(o); }
    { FILE *q = fopen(NPT "/vloerhulp.pid", "r"); int op = 0; if (q) { if (fscanf(q, "%d", &op) != 1) op = 0; fclose(q); }
      if (op > 0 && op != getpid() && kill(op, 0) == 0) { snprintf(b, sizeof b, "/proc/%d/cmdline", op); char c[256];
          if (rd(b, c, sizeof c) > 0 && strstr(c, "vloerhulp")) return 0; } }   // one instance
    lg = fopen(HERE "/vloerhulp.log", "a");
    FILE *pf = fopen(NPT "/vloerhulp.pid", "w"); if (pf) { fprintf(pf, "%d\n", getpid()); fclose(pf); }
    int fd = open(NPT "/sein", O_WRONLY | O_CREAT, 0666); if (fd >= 0) close(fd); chmod(NPT "/sein", 0666);
    int in = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (in < 0 || inotify_add_watch(in, NPT "/sein", IN_ATTRIB | IN_CLOSE_WRITE | IN_MODIFY) < 0) { logf_("inotify faalt: %s", strerror(errno)); return 1; }
    int probe = set_uclamp(getpid(), 0); if (probe != 0) uclamp_ok = 0;
    logf_("gestart pid %d: boost gpu %d, hold %d ms, uclamp %s (%d), basis gpu %d cpu %s/%s", getpid(), BOOST_GPU, HOLD_MS,
          uclamp_ok ? "ja" : "nee", UCLAMP, BASE_GPU, cpu0_orig, cpu6_orig);
    int64_t last = -100000, check = 0, inboost = 0, t0 = ms(), lastlog = ms(); long touches = 0, boosts = 0;
    for (;;) {
        int64_t now = ms();
        int wait = state == BOOST ? (int)(last + HOLD_MS - now) : 1000; if (wait > 1000) wait = 1000; if (wait < 0) wait = 0;
        struct pollfd p = { in, POLLIN, 0 };
        int r = poll(&p, 1, wait); now = ms();
        if (r > 0) { char ev[1024]; while (read(in, ev, sizeof ev) > 0) {} touches++;
            if (state != UIT) { last = now; if (state != BOOST) { boosts++; inboost -= now; apply(BOOST); } } }
        if (state == BOOST && now - last >= HOLD_MS) { inboost += now; apply(BASIS); }
        if (now - check >= 1000) {
            check = now;
            if (exists(NPT "/boost-signaal-uit")) { if (state == BOOST) inboost += now; apply(UIT); logf_("boost-signaal-uit: gestopt"); break; }
            int va = vm_alive(), li = lit(), on = va && li;
            if (getenv("VH_DEBUG")) logf_("debug: vm=%d lit=%d state=%d touches=%ld", va, li, state, touches);
            if (!on && state != UIT) { if (state == BOOST) inboost += now; apply(UIT); logf_("VM niet op scherm: alles terug"); }
            else if (on && state == UIT) { apply(BASIS); }
            else if (on) { snprintf(b, sizeof b, "%d", state == BOOST ? BOOST_GPU : BASE_GPU); char c[32]; if (rd(K "/min_clock_mhz", c, sizeof c) >= 0 && strcmp(b, c)) puti(K "/min_clock_mhz", atoi(b));
                if (state == BOOST && use_uclamp()) vm_threads(UCLAMP); }   // new threads (render server children)
            if (now - lastlog >= 600000) { lastlog = now; logf_("tellers: aanrakingen %ld, boosts %ld, in boost %lld s van %lld s", touches, boosts,
                (long long)((inboost + (state == BOOST ? now : 0)) / 1000), (long long)((now - t0) / 1000)); }
        }
    }
    unlink(NPT "/vloerhulp.pid");
    return 0;
}
