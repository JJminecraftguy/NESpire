#include <stdint.h>
#include <string.h>
#include <libndls.h>

#define SCREEN_W 320
#define SCREEN_H 240
#define FB_BYTES (SCREEN_W * SCREEN_H * 2u)   /* 0x25800 */

/* Non-static so ppu.S / menu.S can reference it directly via
 * "ldr rN, =disp_fb" — avoids the disp_get_fb() call and the
 * register-clobber bug in display_char_withcolor. */
uint16_t disp_fb[SCREEN_W * SCREEN_H] __attribute__((aligned(64)));

#define MODEL_REG      (*(volatile uint32_t *)0x900A0000u)
#define PL111_UPBASE   (*(volatile uint32_t *)0xC0000010u)
#define CX2_MAGIC_VRAM ((uint16_t *)0xA8000000u)

typedef enum { DISP_CLASSIC, DISP_HWW, DISP_CX2, DISP_NONE } disp_mode_t;

static disp_mode_t mode = DISP_NONE;
static uint32_t    saved_upbase;

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

    /* CX II: ASIC id 0x0202 in low 16 bits */
    if ((id & 0xFFFFu) == 0x0202u) {
        mode = DISP_CX2;
        return 1;
    }

    /* CX (both 0x101 and 0x1001 seen in the wild) */
    if (id == 0x00000101u || id == 0x10000101u) {
        scr_type_t t = lcd_type();
        if (t == SCR_240x320_565 || t == SCR_240x320_555) {
            /* HW-W+ portrait SPI panel */
            if (!lcd_init(SCR_320x240_565)) {
                mode = DISP_NONE;
                return 0;
            }
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

/* CX II: 32-byte-per-iter ldm/stm copy into uncached magic VRAM. */
static void cx2_flip(void)
{
    const uint32_t *src = (const uint32_t *)disp_fb;
    uint32_t       *dst = (uint32_t *)CX2_MAGIC_VRAM;
    uint32_t words = FB_BYTES / 4u;

    while (words >= 8) {
        asm volatile(
            "ldmia %0!, {r3-r10}\n"
            "stmia %1!, {r3-r10}\n"
            : "+r"(src), "+r"(dst)
            :
            : "r3","r4","r5","r6","r7","r8","r9","r10","memory");
        words -= 8;
    }
    while (words--) *dst++ = *src++;
}

void disp_flip(void)
{
    switch (mode) {
        case DISP_CLASSIC:
            cache_clean_fb();              /* PL111 DMA reads cached SDRAM */
            break;
        case DISP_HWW:
            lcd_blit(disp_fb, SCR_320x240_565);
            break;
        case DISP_CX2:
            cx2_flip();                    /* uncached SRAM, no cache maintenance */
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
