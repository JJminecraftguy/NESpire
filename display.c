#include <stdint.h>
#include <string.h>
#include <libndls.h>

#define SCREEN_W 320
#define SCREEN_H 240
#define FB_BYTES (SCREEN_W * SCREEN_H * 2u)   /* 0x25800 */

/* Non-static so ppu.S / menu.S can reference it via "ldr rN, =disp_fb". */
uint16_t disp_fb[SCREEN_W * SCREEN_H] __attribute__((aligned(64)));

#define MODEL_REG      (*(volatile uint32_t *)0x900A0000u)
#define PL111_UPBASE   (*(volatile uint32_t *)0xC0000010u)

typedef enum { DISP_CLASSIC, DISP_HWW, DISP_CX2, DISP_NONE } disp_mode_t;

static disp_mode_t  mode = DISP_NONE;
static uint32_t     saved_upbase;
static uint16_t    *cx2_target = NULL;   /* PL111_UPBASE target on CX II */

/* Defined before disp_init so it's visible to it. */
static void cache_clean_fb(void)
{
    uint32_t a = (uint32_t)disp_fb, end = a + FB_BYTES;
    for (; a < end; a += 32u)
        asm volatile("mcr p15, 0, %0, c7, c10, 1" :: "r"(a));
    asm volatile("mcr p15, 0, %0, c7, c10, 4" :: "r"(0));
}

int disp_init(void)
{
    uint32_t id = MODEL_REG;

    /* CX II: whatever PL111_UPBASE points at is the OS display buffer.
     * The original code wrote there per-scanline and it worked. */
    if ((id & 0xFFFFu) == 0x0202u) {
        cx2_target = (uint16_t *)PL111_UPBASE;
        if (!cx2_target) { mode = DISP_NONE; return 0; }
        mode = DISP_CX2;
        return 1;
    }

    /* CX */
    if (id == 0x00000101u || id == 0x10000101u) {
        scr_type_t t = lcd_type();
        if (t == SCR_240x320_565 || t == SCR_240x320_555) {
            /* HW-W+ portrait SPI panel */
            if (!lcd_init(SCR_320x240_565)) { mode = DISP_NONE; return 0; }
            mode = DISP_HWW;
        } else {
            /* Classic CX landscape PL111 panel */
            saved_upbase = PL111_UPBASE;
            PL111_UPBASE = (uint32_t)disp_fb;
            cache_clean_fb();
            mode = DISP_CLASSIC;
        }
        return 1;
    }
    return 0;
}

static void cx2_flip(void)
{
    /* Copy into the real display buffer (PL111_UPBASE's target),
     * not a hardcoded address. memcpy preserves callee-saved regs
     * including r9. */
    memcpy(cx2_target, disp_fb, FB_BYTES);
}

void disp_flip(void)
{
    switch (mode) {
        case DISP_CLASSIC:
            cache_clean_fb();
            break;
        case DISP_HWW:
            lcd_blit(disp_fb, SCR_320x240_565);
            break;
        case DISP_CX2:
            cx2_flip();
            break;
        default:
            break;
    }
}

void disp_shutdown(void)
{
    switch (mode) {
        case DISP_CLASSIC:
            PL111_UPBASE = saved_upbase;
            refresh_osscr();
            break;
        case DISP_HWW:
            lcd_init(SCR_TYPE_INVALID);
            break;
        case DISP_CX2:
            refresh_osscr();
            break;
        default:
            break;
    }
    mode = DISP_NONE;
}
