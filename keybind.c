/*
 * keybind.c -- configurable key bindings for NESpire.
 *
 * Built with -ffixed-r9 (see Makefile) because r9 holds the emulator state
 * pointer in the assembly code and display_string() (asm) needs it.
 *
 * Public entry points (called from the assembly code):
 *   kb_init(path, filename_ptr)  load saved bindings (or defaults)
 *   kb_read_input()              NES controller bitmask (same layout as before)
 *   kb_read_commands()           emulator command bitmask (+ bit 10 = open menu)
 *   kb_read_menu_input()         fixed keys used by the ROM selection menu
 *   kb_menu()                    the rebind menu itself
 */
#include <os.h>
#include <libndls.h>
#include <stdint.h>

extern uint16_t disp_fb[];
extern void disp_flip(void);
extern void display_string(const char *s, int start, int end, int color);

/* ------------------------------------------------------------------ */
/* Key table                                                           */
/* ------------------------------------------------------------------ */

typedef struct {
    const t_key *key;
    const char  *name;
} kdef;

#define K(x, n) { &KEY_NSPIRE_##x, n }

static const kdef keys[] = {
    /* Arrows */
    K(UP, "Up"), K(UPRIGHT, "UpRight"), K(RIGHT, "Right"),
    K(RIGHTDOWN, "RightDown"), K(DOWN, "Down"), K(DOWNLEFT, "DownLeft"),
    K(LEFT, "Left"), K(LEFTUP, "LeftUp"), K(CLICK, "Click"),
    /* Numbers */
    K(0, "0"), K(1, "1"), K(2, "2"), K(3, "3"), K(4, "4"),
    K(5, "5"), K(6, "6"), K(7, "7"), K(8, "8"), K(9, "9"),
    /* Letters */
    K(A, "A"), K(B, "B"), K(C, "C"), K(D, "D"), K(E, "E"), K(F, "F"),
    K(G, "G"), K(H, "H"), K(I, "I"), K(J, "J"), K(K, "K"), K(L, "L"),
    K(M, "M"), K(N, "N"), K(O, "O"), K(P, "P"), K(Q, "Q"), K(R, "R"),
    K(S, "S"), K(T, "T"), K(U, "U"), K(V, "V"), K(W, "W"), K(X, "X"),
    K(Y, "Y"), K(Z, "Z"),
    /* Math / symbols */
    K(PLUS, "Plus"), K(MINUS, "Minus"), K(MULTIPLY, "Multiply"),
    K(DIVIDE, "Divide"), K(EQU, "Equal"), K(COLON, "Colon"),
    K(COMMA, "Comma"), K(PERIOD, "Period"), K(QUES, "Question"),
    K(QUESEXCL, "QuesExcl"), K(APOSTROPHE, "Apostrophe"), K(QUOTE, "Quote"),
    K(BAR, "Bar"), K(EE, "EE"), K(PI, "Pi"), K(LTHAN, "LessThan"),
    K(GTHAN, "GreaterThan"), K(LP, "LeftParen"), K(RP, "RightParen"),
    K(NEGATIVE, "Negative"), K(TENX, "TenX"), K(VAR, "Var"),
    K(FRAC, "Frac"), K(THETA, "Theta"), K(TRIG, "Trig"),
    K(SCRATCHPAD, "Scratchpad"), K(COS, "Cos"), K(SIN, "Sin"),
    K(TAN, "Tan"), K(EXP, "Exp"), K(eEXP, "e^x"), K(SQU, "x^2"),
    K(II, "i^2"),
    /* Function / control */
    K(ESC, "Esc"), K(SHIFT, "Shift"), K(CTRL, "Ctrl"), K(MENU, "Menu"),
    K(HOME, "Home"), K(FLAG, "Flag"), K(TAB, "Tab"), K(DEL, "Delete"),
    K(DOC, "Doc"), K(ENTER, "Enter"), K(RET, "Return"), K(SPACE, "Space"),
};
#define NKEYS ((int)(sizeof(keys) / sizeof(keys[0])))

/* ------------------------------------------------------------------ */
/* Actions                                                             */
/* ------------------------------------------------------------------ */

typedef struct {
    const char *label;
    uint32_t    mask;     /* NES button bit, or emulator command bit */
} action_t;

/* NES controller bits (must match what memory.S / the old asm used) */
static const action_t actions[] = {
    /* ---- Game: player 1 ---- */
    { "P1 A button",          0x00001 },
    { "P1 B button",          0x00002 },
    { "P1 Select",            0x00004 },
    { "P1 Start",             0x00008 },
    { "P1 D-pad Up",          0x00010 },
    { "P1 D-pad Down",        0x00020 },
    { "P1 D-pad Left",        0x00040 },
    { "P1 D-pad Right",       0x00080 },
    /* ---- Game: player 2 ---- */
    { "P2 A button",          0x10000 },
    { "P2 B button",          0x20000 },
    { "P2 Select",            0x40000 },
    { "P2 Start",             0x80000 },
    { "P2 D-pad Up",          0x100000 },
    { "P2 D-pad Down",        0x200000 },
    { "P2 D-pad Left",        0x400000 },
    { "P2 D-pad Right",       0x800000 },
    { "P2 Microphone",        0x00100 },
    /* ---- Emulator (bit numbers match newframe in main.S) ---- */
    { "Frameskip up",         1u << 0 },
    { "Frameskip down",       1u << 1 },
    { "Save state",           1u << 2 },
    { "Load state",           1u << 3 },
    { "Border black/white",   1u << 4 },
    { "Pause",                1u << 5 },
    { "Quit emulator",        1u << 6 },
    { "Invert colors",        1u << 7 },
    { "Write save file",      1u << 8 },
    { "Fast-forward (hold)",  1u << 9 },
    { "Open key menu",        1u << 10 },
    { "Game menu / resume",   1u << 11 },
    { "Reset emulator",       1u << 12 },
    /* ---- ROM list menu (bit values match menu.S) ---- */
    { "List: move up",        0x10 },
    { "List: move down",      0x20 },
    { "Exit program",         0x01 },
    { "Start selected game",  0x100 },
};
#define NACT      ((int)(sizeof(actions) / sizeof(actions[0])))
#define NES_FIRST 0
#define NES_COUNT 17
#define EMU_FIRST 17
#define EMU_COUNT 13
#define ACT_OPENMENU 27
#define ACT_GAMEMENU 28
#define ACT_RESET 29
#define ACT_LIST_FIRST 30
#define ACT_LIST_COUNT 4

static uint8_t bind[NACT];
static int g_touch, g_classic;

/* ------------------------------------------------------------------ */
/* Low level key reading                                               */
/* ------------------------------------------------------------------ */

static int tp_valid, tp_arrow;

static int tp_get(void)
{
    if (!tp_valid) {
        touchpad_report_t r;
        touchpad_scan(&r);
        tp_arrow = r.pressed ? (int)r.arrow : TPAD_ARROW_NONE;
        tp_valid = 1;
    }
    return tp_arrow;
}

static int key_exists(const t_key *k)
{
    int r = g_touch ? k->tpad_row : k->row;
    int c = g_touch ? k->tpad_col : k->col;
    return !(r == _KEY_DUMMY_ROW && c == _KEY_DUMMY_COL);
}

static int key_down(const t_key *k)
{
    if (g_touch && k->tpad_arrow != TPAD_ARROW_NONE) {
        int a = tp_get();
        /* Corners of the touchpad count as both neighbouring directions,
         * like the original NESpire touchpad code did. */
        switch (k->tpad_arrow) {
        case TPAD_ARROW_UP:
            return a == TPAD_ARROW_UP || a == TPAD_ARROW_UPRIGHT || a == TPAD_ARROW_LEFTUP;
        case TPAD_ARROW_DOWN:
            return a == TPAD_ARROW_DOWN || a == TPAD_ARROW_RIGHTDOWN || a == TPAD_ARROW_DOWNLEFT;
        case TPAD_ARROW_LEFT:
            return a == TPAD_ARROW_LEFT || a == TPAD_ARROW_DOWNLEFT || a == TPAD_ARROW_LEFTUP;
        case TPAD_ARROW_RIGHT:
            return a == TPAD_ARROW_RIGHT || a == TPAD_ARROW_UPRIGHT || a == TPAD_ARROW_RIGHTDOWN;
        default:
            return a == (int)k->tpad_arrow;
        }
    }
    int row = g_touch ? k->tpad_row : k->row;
    int col = g_touch ? k->tpad_col : k->col;
    int v = !((*(volatile short *)(0x900E0000 + row)) & col);
    return (!g_classic) ^ v;
}

static int kdown(int idx) { return key_down(keys[idx].key); }

static int key_index(const t_key *k)
{
    for (int i = 0; i < NKEYS; i++)
        if (keys[i].key == k) return i;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Defaults / persistence                                              */
/* ------------------------------------------------------------------ */

static void set_defaults(void)
{
    const t_key *d[NACT] = {
        &KEY_NSPIRE_ESC, &KEY_NSPIRE_TAB, &KEY_NSPIRE_DEL, &KEY_NSPIRE_SHIFT,
        &KEY_NSPIRE_UP, &KEY_NSPIRE_DOWN, &KEY_NSPIRE_LEFT, &KEY_NSPIRE_RIGHT,
        g_touch ? &KEY_NSPIRE_EQU : &KEY_NSPIRE_SQU,
        g_touch ? &KEY_NSPIRE_EXP : &KEY_NSPIRE_TENX,
        &KEY_NSPIRE_VAR, &KEY_NSPIRE_CTRL,
        &KEY_NSPIRE_8, &KEY_NSPIRE_5, &KEY_NSPIRE_4, &KEY_NSPIRE_6,
        &KEY_NSPIRE_MENU,
        &KEY_NSPIRE_PLUS, &KEY_NSPIRE_MINUS, &KEY_NSPIRE_7, &KEY_NSPIRE_9,
        &KEY_NSPIRE_B, &KEY_NSPIRE_P, &KEY_NSPIRE_Q, &KEY_NSPIRE_I,
        &KEY_NSPIRE_S, &KEY_NSPIRE_MULTIPLY,
        &KEY_NSPIRE_C, &KEY_NSPIRE_M, &KEY_NSPIRE_R,
        &KEY_NSPIRE_UP, &KEY_NSPIRE_DOWN, &KEY_NSPIRE_ESC, &KEY_NSPIRE_MENU,
    };
    for (int i = 0; i < NACT; i++)
        bind[i] = (uint8_t)key_index(d[i]);
}

static uint8_t default_of(int act)
{
    uint8_t saved[NACT];
    for (int i = 0; i < NACT; i++) saved[i] = bind[i];
    set_defaults();
    uint8_t r = bind[act];
    for (int i = 0; i < NACT; i++) bind[i] = saved[i];
    return r;
}

#define CFG_NAME "nespire.keys.tns"
static char cfg_path[512];
static int  cfg_ok;

#define CFG_MAGIC0 'N'
#define CFG_MAGIC1 'K'
#define CFG_VERSION 1

void kb_save(void)
{
    if (!cfg_ok) return;
    uint8_t buf[4 + NACT];
    buf[0] = CFG_MAGIC0; buf[1] = CFG_MAGIC1; buf[2] = CFG_VERSION; buf[3] = NACT;
    for (int i = 0; i < NACT; i++) buf[4 + i] = bind[i];
    NUC_FILE *f = nuc_fopen(cfg_path, "wb");
    if (!f) return;
    nuc_fwrite(buf, 1, sizeof(buf), f);
    nuc_fclose(f);
}

static void kb_load(void)
{
    if (!cfg_ok) return;
    uint8_t buf[4 + NACT];
    NUC_FILE *f = nuc_fopen(cfg_path, "rb");
    if (!f) return;
    size_t n = nuc_fread(buf, 1, sizeof(buf), f);
    nuc_fclose(f);
    if (n != sizeof(buf) || buf[0] != CFG_MAGIC0 || buf[1] != CFG_MAGIC1 ||
        buf[2] != CFG_VERSION || buf[3] != NACT)
        return;
    for (int i = 0; i < NACT; i++)
        if (buf[4 + i] >= NKEYS) return;
    for (int i = 0; i < NACT; i++) bind[i] = buf[4 + i];
}

/* folder = start of path buffer, fname = pointer just past the folder part */
void kb_init(const char *folder, const char *fname)
{
    g_touch   = is_touchpad;
    g_classic = is_classic;

    set_defaults();

    int len = (int)(fname - folder);
    if (len >= 0 && len < (int)sizeof(cfg_path) - (int)sizeof(CFG_NAME)) {
        for (int i = 0; i < len; i++) cfg_path[i] = folder[i];
        for (int i = 0; i < (int)sizeof(CFG_NAME); i++) cfg_path[len + i] = CFG_NAME[i];
        cfg_ok = 1;
        kb_load();
    }
}

/* ------------------------------------------------------------------ */
/* Polling used by the emulator                                        */
/* ------------------------------------------------------------------ */

uint32_t kb_read_input(void)
{
    uint32_t r = 0;
    tp_valid = 0;
    for (int i = NES_FIRST; i < NES_FIRST + NES_COUNT; i++)
        if (kdown(bind[i])) r |= actions[i].mask;
    return r;
}

uint32_t kb_read_commands(void)
{
    uint32_t r = 0;
    tp_valid = 0;
    for (int i = EMU_FIRST; i < EMU_FIRST + EMU_COUNT; i++)
        if (kdown(bind[i])) r |= actions[i].mask;
    return r;
}

/* ROM selection menu input.
 * 0x01 = leave, 0x10 = up, 0x20 = down, 0x100 = start,
 * 0x200 = key menu, 0x400 = back to the running game */
uint32_t kb_read_menu_input(void)
{
    uint32_t r = 0;
    tp_valid = 0;
    for (int i = ACT_LIST_FIRST; i < ACT_LIST_FIRST + ACT_LIST_COUNT; i++)
        if (kdown(bind[i])) r |= actions[i].mask;
    if (kdown(bind[ACT_OPENMENU])) r |= 0x200;
    if (kdown(bind[ACT_GAMEMENU])) r |= 0x400;
    return r;
}

/* ------------------------------------------------------------------ */
/* Rebind menu                                                         */
/* ------------------------------------------------------------------ */

#define ROWS        15
#define LIST_ROWS   13          /* rows 1..13 */
#define COLS        40
#define ROW_CELLS   640

static void wait_tick(void)
{
    asm volatile("mcr p15, 0, %0, c7, c0, 4" :: "r"(0) : "memory");
}

static int any_key_down(void)
{
    tp_valid = 0;
    for (int i = 0; i < NKEYS; i++)
        if (key_exists(keys[i].key) && kdown(i)) return 1;
    return 0;
}

static void wait_release(void)
{
    while (any_key_down()) wait_tick();
}

void kb_wait_release(void) { wait_release(); }

static void put(char *line, int col, const char *s)
{
    for (; *s && col < COLS; s++, col++) line[col] = *s;
}

static void draw_row(int row, const char *text_line, int reverse)
{
    display_string(text_line, row * ROW_CELLS, row * ROW_CELLS + COLS, reverse ? -1 : 0);
}

/* Two pages: 0 = game + emulator keys, 1 = ROM list keys */
static int page_count(int p) { return p == 0 ? ACT_RESET + 1 : ACT_LIST_COUNT + 2; }
static int page_act(int p, int i)
{
    if (p == 0) return i;
    if (i < ACT_LIST_COUNT) return ACT_LIST_FIRST + i;
    return i == ACT_LIST_COUNT ? ACT_OPENMENU : ACT_GAMEMENU;
}

static void draw_menu(int page, int sel, int top, int capturing, const char *msg)
{
    char line[COLS + 1];
    int count = page_count(page);

    for (int i = 0; i < COLS; i++) line[i] = ' ';
    line[COLS] = 0;
    put(line, 1, page == 0 ? "< Game + emulator keys >" : "< ROM list keys >");
    put(line, 29, "Esc=close");
    draw_row(0, line, 1);

    for (int r = 0; r < LIST_ROWS; r++) {
        int idx = top + r;
        for (int i = 0; i < COLS; i++) line[i] = ' ';
        if (idx < count) {
            int a = page_act(page, idx);
            line[0] = (idx == sel) ? '\x10' : ' ';
            put(line, 2, actions[a].label);
            if (idx == sel && capturing)
                put(line, 25, "press a key...");
            else
                put(line, 25, keys[bind[a]].name);
        }
        draw_row(1 + r, line, idx == sel);
    }

    for (int i = 0; i < COLS; i++) line[i] = ' ';
    if (msg)
        put(line, 1, msg);
    else if (capturing)
        put(line, 1, "Press new key  (Enter = cancel)");
    else
        put(line, 1, "Enter=Rebind  Del=Default  L/R=Page");
    draw_row(ROWS - 1, line, 1);

    disp_flip();
}

enum { EV_NONE, EV_UP, EV_DOWN, EV_LEFT, EV_RIGHT, EV_ENTER, EV_ESC, EV_DEL, EV_MENUKEY };

static int poll_event(void)
{
    tp_valid = 0;
    if (key_down(&KEY_NSPIRE_ENTER)) return EV_ENTER;
    if (key_down(&KEY_NSPIRE_UP))    return EV_UP;
    if (key_down(&KEY_NSPIRE_DOWN))  return EV_DOWN;
    if (key_down(&KEY_NSPIRE_LEFT))  return EV_LEFT;
    if (key_down(&KEY_NSPIRE_RIGHT)) return EV_RIGHT;
    if (key_down(&KEY_NSPIRE_ESC))   return EV_ESC;
    if (key_down(&KEY_NSPIRE_DEL))   return EV_DEL;
    if (kdown(bind[ACT_OPENMENU]))   return EV_MENUKEY;
    return EV_NONE;
}

/* Block until a new event occurs (with auto-repeat for up/down). */
static int wait_event(void)
{
    static int prev = EV_NONE;
    static int hold = 0;
    for (;;) {
        wait_tick();
        int e = poll_event();
        if (e != prev) {
            prev = e;
            hold = 25;
            if (e != EV_NONE) return e;
        } else if ((e == EV_UP || e == EV_DOWN) && --hold <= 0) {
            hold = 5;
            return e;
        }
    }
}

/* Returns the table index of the newly pressed key, or -1 if cancelled
 * (Enter is reserved: it can never be bound). */
static int capture_key(void)
{
    wait_release();
    for (;;) {
        wait_tick();
        tp_valid = 0;
        for (int i = 0; i < NKEYS; i++) {
            if (!key_exists(keys[i].key) || !kdown(i)) continue;
            if (keys[i].key == &KEY_NSPIRE_ENTER) return -1;
            return i;
        }
    }
}

/* Caller must clear_screen()/redraw afterwards. */
void kb_menu(void)
{
    int page = 0, sel = 0, top = 0, changed = 0;
    const char *msg = 0;
    char msgbuf[COLS + 1];

    wait_release();

    for (;;) {
        int count = page_count(page);
        if (sel < top) top = sel;
        if (sel >= top + LIST_ROWS) top = sel - LIST_ROWS + 1;
        draw_menu(page, sel, top, 0, msg);
        msg = 0;

        int e = wait_event();
        int a = page_act(page, sel);
        if (e == EV_ESC || e == EV_MENUKEY)
            break;
        if (e == EV_UP)   { if (sel > 0) sel--; }
        else if (e == EV_DOWN) { if (sel < count - 1) sel++; }
        else if (e == EV_LEFT || e == EV_RIGHT) {
            page ^= 1;
            sel = top = 0;
        }
        else if (e == EV_DEL) {
            uint8_t d = default_of(a);
            for (int j = 0; j < NACT; j++)
                if (j != a && bind[j] == d) bind[j] = bind[a];  /* swap */
            bind[a] = d;
            changed = 1;
            msg = "Reset to default";
        }
        else if (e == EV_ENTER) {
            draw_menu(page, sel, top, 1, 0);
            int k = capture_key();
            if (k >= 0) {
                int swapped = -1;
                for (int j = 0; j < NACT; j++)
                    if (j != a && bind[j] == k) { swapped = j; bind[j] = bind[a]; }
                bind[a] = (uint8_t)k;
                changed = 1;
                if (swapped >= 0) {
                    int n = 0;
                    const char *p = "Swapped with ";
                    for (; *p; p++) msgbuf[n++] = *p;
                    for (p = actions[swapped].label; *p && n < COLS - 1; p++) msgbuf[n++] = *p;
                    msgbuf[n] = 0;
                    msg = msgbuf;
                }
            }
            wait_release();
        }
    }

    if (changed) kb_save();
    wait_release();
}
