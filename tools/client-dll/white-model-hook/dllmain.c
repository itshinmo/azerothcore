/*
 * DivxDecoder proxy: white-model probe.
 *
 * Stock Wow.exe imports four functions from DivxDecoder.dll, so the Windows loader loads this file
 * for every player who copies it beside the executable. The four exports are **forwarders** declared
 * in DivxDecoder.def: the loader resolves them against DivxDecoder_orig.dll before any game code
 * runs, so the video path can never be left with a null function pointer.
 *
 * This build probes five candidate functions on the Journal preview path and counts hits. It changes
 * no behaviour and textures nothing.
 *
 * Target addresses are fixed VAs for one pinned exe. They are only patched when the image base is
 * 0x400000, every target lies inside the mapped image, and every prologue matches its expected
 * bytes; otherwise the probe is skipped and logged. That is a guard against a wrong build, not a
 * substitute for it: pairing a different 0x400000-based exe with matching generic prologues is not
 * detectable here.
 *
 * Contract: decisions/ADR-036-client-dll-patches.md.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

/* 0 = forwarding only. 1 = with probes. */
#ifndef ENABLE_DETOUR
#define ENABLE_DETOUR 0
#endif

#ifndef BUILD_ID
#define BUILD_ID "dev"
#endif

#if ENABLE_DETOUR
void probe0(void) __asm__("_probe0");
void probe1(void) __asm__("_probe1");
void probe2(void) __asm__("_probe2");
void probe3(void) __asm__("_probe3");
void probe4(void) __asm__("_probe4");
#endif

/* Stub targets and counters; outside the guard because hook.S is always linked. */
void *g_resume0 = NULL;
void *g_resume1 = NULL;
void *g_resume2 = NULL;
void *g_resume3 = NULL;
void *g_resume4 = NULL;
volatile LONG g_count0 = 0;
volatile LONG g_count1 = 0;
volatile LONG g_count2 = 0;
volatile LONG g_count3 = 0;
volatile LONG g_count4 = 0;

/* ---------------------------------------------------------------- logging */

static char g_log_path[MAX_PATH];

static void log_open(HINSTANCE inst)
{
    char *slash = NULL;
    char *p;
    DWORD n;

    n = GetModuleFileNameA(inst, g_log_path, MAX_PATH);
    if (!n || n >= MAX_PATH) {
        g_log_path[0] = 0;
        return;
    }
    for (p = g_log_path; *p; p++)
        if (*p == '\\' || *p == '/')
            slash = p;
    if (slash) {
        /* remaining capacity after the separator, so a deep install path cannot overflow */
        DWORD used = (DWORD)(slash + 1 - g_log_path);
        DWORD left = (DWORD)MAX_PATH - used;
        if (left < 32) {
            g_log_path[0] = 0;
            return;
        }
        lstrcpynA(slash + 1, "white-model-hook.log", (int)left);
    }
}

static void append_str(char *out, int *pos, const char *text)
{
    while (*text && *pos < 400)
        out[(*pos)++] = *text++;
}

__attribute__((unused))
static void append_uint(char *out, int *pos, unsigned long value)
{
    char tmp[16];
    int n = 0;
    if (!value)
        tmp[n++] = '0';
    while (value) {
        tmp[n++] = (char)('0' + (value % 10));
        value /= 10;
    }
    while (n > 0 && *pos < 400)
        out[(*pos)++] = tmp[--n];
}

__attribute__((unused))
static void append_hex(char *out, int *pos, unsigned long value)
{
    const char *digits = "0123456789abcdef";
    char tmp[16];
    int n = 0;
    append_str(out, pos, "0x");
    if (!value)
        tmp[n++] = '0';
    while (value) {
        tmp[n++] = digits[value & 0xF];
        value >>= 4;
    }
    while (n > 0 && *pos < 400)
        out[(*pos)++] = tmp[--n];
}

static void log_line(const char *msg)
{
    HANDLE f;
    DWORD written;
    char line[512];
    int i = 0;

    if (!g_log_path[0])
        return;
    append_str(line, &i, "white-model-hook: ");
    for (const char *s = msg; *s && i < 500; s++)
        line[i++] = *s;
    line[i++] = '\r';
    line[i++] = '\n';

    f = CreateFileA(g_log_path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
                    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return;
    WriteFile(f, line, (DWORD)i, &written, NULL);
    CloseHandle(f);
}

/* ---------------------------------------------------------------- probes */

#define PROBE_COUNT 5

typedef struct {
    unsigned int va;
    unsigned int len;               /* bytes displaced; varies per target */
    const char *name;
    void *stub;
    void **resume;
    volatile LONG *count;
    const unsigned char *prologue;
} Probe;

#if ENABLE_DETOUR

/* Measured prologues. `len` must be the exact length of the instructions they cover. */
static const unsigned char kP0[9] = {0x55, 0x8B, 0xEC, 0x51, 0x53, 0x8B, 0x5D, 0x08, 0x57};
static const unsigned char kP1[9] = {0x55, 0x8B, 0xEC, 0x51, 0x8B, 0x45, 0x08, 0x85, 0xC0};
static const unsigned char kP2[9] = {0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08, 0x56, 0x8B, 0xF1};
static const unsigned char kP3[14] = {0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08, 0x33, 0xD2,
                                      0x39, 0x91, 0xE0, 0x00, 0x00, 0x00};
static const unsigned char kP4[9] = {0x55, 0x8B, 0xEC, 0x56, 0x8B, 0x75, 0x08, 0x6A, 0x01};

static Probe g_probes[PROBE_COUNT] = {
    {0x005975E0u,  9, "0x5975e0 record->display", NULL, &g_resume0, &g_count0, kP0},
    {0x00597700u,  9, "0x597700 display build   ", NULL, &g_resume1, &g_count1, kP1},
    {0x005977E0u,  9, "0x5977e0 SetCreature     ", NULL, &g_resume2, &g_count2, kP2},
    {0x00597840u, 14, "0x597840 set display id  ", NULL, &g_resume3, &g_count3, kP3},
    {0x0084F280u,  9, "0x84f280 model setter    ", NULL, &g_resume4, &g_count4, kP4},
};

/* Is [addr, addr+len) inside a committed, readable region of the current process? */
static int is_readable(const void *addr, unsigned int len)
{
    const unsigned char *p = (const unsigned char *)addr;
    const unsigned char *end = p + len;
    MEMORY_BASIC_INFORMATION mbi;

    while (p < end) {
        if (VirtualQuery(p, &mbi, sizeof(mbi)) != sizeof(mbi))
            return 0;
        if (mbi.State != MEM_COMMIT)
            return 0;
        if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD))
            return 0;
        p = (const unsigned char *)mbi.BaseAddress + mbi.RegionSize;
    }
    return 1;
}

static int patch_one(Probe *p, void *stub)
{
    unsigned char *target = (unsigned char *)(uintptr_t)p->va;
    unsigned char jump[16];
    unsigned int q;
    DWORD old;
    unsigned int i;
    intptr_t delta;

    if (!is_readable(target, p->len))
        return 0;
    for (i = 0; i < p->len; i++)
        if (target[i] != p->prologue[i])
            return 0;

    /* rel32 is signed 32-bit; refuse anything outside that range rather than wrap. */
    delta = (unsigned char *)stub - (target + 5);
    if (delta > 0x7FFFFFFF || delta < -0x7FFFFFFF)
        return 0;

    *p->resume = (void *)(target + p->len);
    for (q = 0; q < p->len; q++)
        jump[q] = 0x90;
    jump[0] = 0xE9;
    *(int *)(jump + 1) = (int)delta;

    if (!VirtualProtect(target, p->len, PAGE_EXECUTE_READWRITE, &old))
        return 0;
    /* Safe without suspending threads only because this DLL loads statically, before the game
     * starts its own threads. Never FreeLibrary while a detour is installed. */
    for (i = 0; i < p->len; i++)
        target[i] = jump[i];
    VirtualProtect(target, p->len, old, &old);
    FlushInstructionCache(GetCurrentProcess(), target, p->len);
    return 1;
}

static void report_counts(int final)
{
    char msg[400];
    int i;

    for (int k = 0; k < PROBE_COUNT; k++) {
        i = 0;
        append_str(msg, &i, g_probes[k].name);
        append_str(msg, &i, " = ");
        append_uint(msg, &i, (unsigned long)*g_probes[k].count);
        msg[i] = 0;
        log_line(msg);
    }
    if (final)
        log_line("final counts");
}

/* Counts are logged only when they change, so a long session cannot grow the log without bound. */
static DWORD WINAPI count_poller(LPVOID param)
{
    LONG last[PROBE_COUNT];
    int z;
    (void)param;

    for (z = 0; z < PROBE_COUNT; z++)
        last[z] = 0;

    for (;;) {
        int changed = 0;
        Sleep(3000);
        for (int k = 0; k < PROBE_COUNT; k++) {
            LONG now = *g_probes[k].count;
            if (now != last[k]) {
                last[k] = now;
                changed = 1;
            }
        }
        if (changed)
            report_counts(0);
    }
    return 0;
}

#endif /* ENABLE_DETOUR */

/* ---------------------------------------------------------------- startup */

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;

    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        log_open(inst);
        log_line("build " BUILD_ID);
#if ENABLE_DETOUR
        {
            char msg[400];
            int i = 0;
            HANDLE t;
            const void *base = (const void *)GetModuleHandleA(NULL);

            if ((uintptr_t)base != 0x400000u) {
                log_line("exe base is not 0x400000; probes skipped");
            } else {
                g_probes[0].stub = (void *)probe0;
                g_probes[1].stub = (void *)probe1;
                g_probes[2].stub = (void *)probe2;
                g_probes[3].stub = (void *)probe3;
                g_probes[4].stub = (void *)probe4;

                for (int k = 0; k < PROBE_COUNT; k++) {
                    i = 0;
                    append_str(msg, &i, g_probes[k].name);
                    append_str(msg, &i, patch_one(&g_probes[k], g_probes[k].stub) ? " patched" : " SKIPPED");
                    msg[i] = 0;
                    log_line(msg);
                }
                t = CreateThread(NULL, 0, count_poller, NULL, 0, NULL);
                if (t)
                    CloseHandle(t);
            }
        }
#else
        log_line("forwarding only; probes not built in");
#endif
    } else if (reason == DLL_PROCESS_DETACH) {
#if ENABLE_DETOUR
        report_counts(1);
#else
        log_line("unload");
#endif
    }
    return TRUE;
}
