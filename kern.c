#include <u.h>
#include "mem.h"

enum {
	VGA_COLOR_BLACK = 0,
	VGA_COLOR_BLUE = 1,
	VGA_COLOR_GREEN = 2,
	VGA_COLOR_CYAN = 3,
	VGA_COLOR_RED = 4,
	VGA_COLOR_MAGENTA = 5,
	VGA_COLOR_BROWN = 6,
	VGA_COLOR_LIGHT_GREY = 7,
	VGA_COLOR_DARK_GREY = 8,
	VGA_COLOR_LIGHT_BLUE = 9,
	VGA_COLOR_LIGHT_GREEN = 10,
	VGA_COLOR_LIGHT_CYAN = 11,
	VGA_COLOR_LIGHT_RED = 12,
	VGA_COLOR_LIGHT_MAGENTA = 13,
	VGA_COLOR_LIGHT_BROWN = 14,
	VGA_COLOR_WHITE = 15,
};

u32int MemMin;
u16int *terminal;

u8int
mkcolor(int fg, int bg)
{
	return fg | bg << 4;
}

u16int
mkchar(uchar c, u8int color)
{
	return (u16int) c | (u16int) color << 8;
}

void
writestr(char *s, int len, u8int color)
{
	int i;
	for(i=0;i<len;i++,s++)
		*(terminal+i) = mkchar(*s, color);
}

void
main(void)
{
	u8int color;
	int i;
	char msg[] = "Barebones kernel from Plan9 space!";
	terminal = (u16int*) 0xB8000;

	color = mkcolor(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
	/* Clear the screen */
	for(i=0;i<25*80;i++)
		*(terminal+i) = mkchar(' ', color);

	/* Print to the screen */
	writestr(msg, sizeof msg-1, color);

	/* Throw her in park */
	for(;;)
		;
}
