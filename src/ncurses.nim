## Minimal ncursesw bindings used by cmatrix-nim.

{.passC: "-DNCURSES_WIDECHAR=1".}
{.passL: "-lncursesw".}

const hdr = "<ncurses.h>"

type
  Window* {.importc: "WINDOW", header: hdr, incompleteStruct.} = object
  Screen* {.importc: "SCREEN", header: hdr, incompleteStruct.} = object
  Chtype* = cuint

const
  ERR* = -1
  COLOR_BLACK* = 0.cshort
  COLOR_RED* = 1.cshort
  COLOR_GREEN* = 2.cshort
  COLOR_YELLOW* = 3.cshort
  COLOR_BLUE* = 4.cshort
  COLOR_MAGENTA* = 5.cshort
  COLOR_CYAN* = 6.cshort
  COLOR_WHITE* = 7.cshort

var
  stdscr* {.importc, header: hdr.}: ptr Window
  LINES* {.importc, header: hdr.}: cint
  COLS* {.importc, header: hdr.}: cint
  A_BOLD* {.importc, header: hdr.}: cint
  A_ALTCHARSET* {.importc, header: hdr.}: cint

{.push importc, header: hdr, cdecl, discardable.}
proc initscr*(): ptr Window
proc newterm*(term: cstring, outfd, infd: File): ptr Screen
proc set_term*(scr: ptr Screen): ptr Screen
proc endwin*(): cint
proc savetty*(): cint
proc resetty*(): cint
proc nonl*(): cint
proc cbreak*(): cint
proc noecho*(): cint
proc timeout*(delay: cint)
proc leaveok*(win: ptr Window, bf: bool): cint
proc curs_set*(visibility: cint): cint
proc has_colors*(): bool
proc start_color*(): cint
proc use_default_colors*(): cint
proc init_pair*(pair, f, b: cshort): cint
proc wgetch*(win: ptr Window): cint
proc addch*(ch: Chtype): cint
proc addstr*(s: cstring): cint
proc attron*(attrs: cint): cint
proc attroff*(attrs: cint): cint
proc napms*(ms: cint): cint
proc refresh*(): cint
proc resizeterm*(lines, cols: cint): cint
proc wresize*(win: ptr Window, lines, cols: cint): cint
proc COLOR_PAIR*(n: cint): cint
{.pop.}

proc moveTo*(y, x: cint): cint {.importc: "move", header: hdr, cdecl, discardable.}
proc clearScreen*(): cint {.importc: "clear", header: hdr, cdecl, discardable.}
