# Makefile for NESpire on TI-Nspire CX / CX II
AS      = nspire-as
CC      = nspire-gcc
LD = nspire-ld
GENZEHN = genzehn

OBJS = $(patsubst %.S, %.o, $(shell find . -name \*.S)) \
       $(patsubst %.c, %.o, $(shell find . -name \*.c))
EXE = nespire

ASFLAGS = -mcpu=arm926ej-s -mtune=arm926ej-s -marm
CFLAGS  = -O3 -mcpu=arm926ej-s -mtune=arm926ej-s -marm -fno-tree-vectorize \
          -ffreestanding -fno-builtin
LDFLAGS = -Wl,--gc-sections

all: $(EXE).tns

$(EXE).tns: $(EXE).elf
	$(GENZEHN) --input $^ --output $@ --compress \
	           --240x320-support true --uses-lcd-blit true

$(EXE).elf: $(OBJS)
	$(LD) $^ -o $@

%.o: %.S nes.inc
	$(AS) $(ASFLAGS) -c $<

%.o: %.c
	$(CC) $(CFLAGS) -c $<

.PHONY: clean
clean:
	-rm -f *.o $(EXE).elf $(EXE).tns
