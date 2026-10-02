#[
    cmatrix-nim: a Nim port of cmatrix.

    Copyright (C) 1999-2017 Chris Allegretta
    Copyright (C) 2017-Present Abishek V Ashok

    cmatrix is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    cmatrix is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with cmatrix. If not, see <http://www.gnu.org/licenses/>.
]#

import std/[os, osproc, posix, random, strutils, termios, unicode]
import ncurses, kana_glyphs

const Version = "2.1.0"

var SIGWINCH {.importc, header: "<signal.h>".}: cint
proc setlocale(category: cint, locale: cstring): cstring {.importc, header: "<locale.h>".}
var LC_ALL {.importc, header: "<locale.h>".}: cint

type Cell = object
  val: int
  isHead: bool

var
  console = false
  xwindow = false
  lock = false
  matrix: seq[seq[Cell]]
  length: seq[int]   # Length of cols in each line
  spaces: seq[int]   # Spaces left to fill
  updates: seq[int]  # Update speed of each column
  signalStatus {.volatile.}: cint = 0
  pixelKana = false  # draw pre-rendered katakana as braille pixel art
  kanaCells: seq[array[4, string]]  # per glyph: top-left, top-right, bottom-left, bottom-right

# In pixel mode each glyph is 4x8 pixels: 2x2 braille cells plus a gap column.
const
  GlyphRows = 2
  GlyphStride = 3

proc gridLines(): int =
  if pixelKana: int(LINES) div GlyphRows else: int(LINES)

proc gridCols(): int =
  if pixelKana: (int(COLS) div GlyphStride) * 2 else: int(COLS)

proc screenX(j: int): cint =
  if pixelKana: cint((j div 2) * GlyphStride) else: cint(j)

proc buildKanaCells() =
  # Braille dot bits for (x, y) inside a 2x4 cell.
  const dot = [[0x01, 0x02, 0x04, 0x40], [0x08, 0x10, 0x20, 0x80]]
  for glyph in KanaGlyphs:
    var cells: array[4, string]
    for c in 0 .. 3:
      let (cx, cy) = (c mod 2, c div 2)
      var bits = 0
      for y in 0 .. 3:
        let row = int(glyph[cy * 4 + y])
        for x in 0 .. 1:
          if (row shr (3 - (cx * 2 + x)) and 1) == 1:
            bits = bits or dot[x][y]
      cells[c] = $Rune(0x2800 + bits)
    kanaCells.add cells

proc emit(row: int, col: cint, val: int, text: string) =
  ## Draws one matrix cell. In pixel mode a katakana becomes a 2x2 block of
  ## braille cells; anything else is drawn top-left with the rest blanked.
  if not pixelKana:
    moveTo(cint(row), col)
    addstr(cstring(text))
    return
  let y = cint(row * GlyphRows)
  if val >= KanaFirst and val <= KanaLast:
    let cells = kanaCells[val - KanaFirst]
    moveTo(y, col); addstr(cstring(cells[0] & cells[1]))
    moveTo(y + 1, col); addstr(cstring(cells[2] & cells[3]))
  else:
    moveTo(y, col); addstr(cstring(text & " "))
    moveTo(y + 1, col); addstr("  ")

proc fontCommand(): string =
  if findExe("consolechars").len > 0: "consolechars"
  elif findExe("setfont").len > 0: "setfont"
  else: ""

proc restoreFont() =
  case fontCommand()
  of "consolechars": discard execCmd("consolechars -d")
  of "setfont": discard execCmd("setfont")
  else: discard

const KDGKBTYPE = 0x4B33  # from <linux/kd.h>

proc isLinuxConsole(fd: cint): bool =
  ## True when fd refers to a Linux virtual console (what setfont and
  ## consolechars need). Graphical terminal emulators and ssh sessions fail.
  when defined(linux):
    var kbType: cchar
    ioctl(fd, KDGKBTYPE, addr kbType) == 0
  else:
    false

var consoleNotice = ""

proc teardown() =
  curs_set(1)
  clearScreen()
  refresh()
  resetty()
  endwin()
  if console:
    restoreFont()
  if consoleNotice.len > 0:
    stderr.writeLine(consoleNotice)

proc finish() =
  teardown()
  quit(0)

proc die(msg: string) =
  teardown()
  stderr.write(msg)
  quit(0)

proc usage() =
  echo " Usage: cmatrix-nim -[abBcfhlsmPVxk] [-u delay] [-C color] [-t tty] [-M message]"
  echo " -a: Asynchronous scroll"
  echo " -b: Bold characters on"
  echo " -B: All bold characters (overrides -b)"
  echo " -c: Use Japanese characters as seen in the original matrix. Requires appropriate fonts"
  echo " -P: Japanese characters pre-rendered as braille pixel art (no CJK font needed)"
  echo " -f: Force the linux $TERM type to be on"
  echo " -l: Linux mode (uses matrix console font)"
  echo " -L: Lock mode (can be closed from another terminal)"
  echo " -o: Use old-style scrolling"
  echo " -h: Print usage and exit"
  echo " -n: No bold characters (overrides -b and -B, default)"
  echo " -s: \"Screensaver\" mode, exits on first keystroke"
  echo " -x: X window mode, use if your xterm is using mtx.pcf"
  echo " -V: Print version information and exit"
  echo " -M [message]: Prints your message in the center of the screen. Overrides -L's default message."
  echo " -u delay (0 - 10, default 4): Screen update delay"
  echo " -C [color]: Use this color for matrix (default green)"
  echo " -r: rainbow mode"
  echo " -m: lambda mode"
  echo " -k: Characters change while scrolling. (Works without -o opt.)"
  echo " -t [tty]: Set tty to use"

proc version() =
  echo " CMatrix (Nim port) version ", Version, " (compiled ", CompileTime, ", ", CompileDate, ")"
  echo "Web: https://github.com/nandi-conda/cmatrix-nim"
  echo "Original: https://github.com/abishekvashok/cmatrix"

proc rnd(n: int): int = rand(max(n, 1) - 1)

proc varInit() =
  let lines = gridLines()
  let cols = gridCols()
  matrix = newSeq[seq[Cell]](lines + 1)
  for i in 0 .. lines:
    matrix[i] = newSeq[Cell](cols)
  length = newSeq[int](cols)
  spaces = newSeq[int](cols)
  updates = newSeq[int](cols)

  # Make the matrix
  for i in 0 .. lines:
    for j in countup(0, cols - 1, 2):
      matrix[i][j].val = -1

  for j in countup(0, cols - 1, 2):
    # How many spaces to skip
    spaces[j] = rnd(lines) + 1
    # And length of the stream
    length[j] = rnd(lines - 3) + 3
    # Sentinel value for creation of new objects
    matrix[1][j].val = ord(' ')
    # Update speed
    updates[j] = rnd(3) + 1

proc sighandler(s: cint) {.noconv.} =
  signalStatus = s

proc resizeScreen() =
  let tty = ttyname(0)
  if tty == nil:
    return
  let fd = posix.open(tty, O_RDWR)
  if fd == -1:
    return
  var win: IOctl_WinSize
  let res = ioctl(fd, TIOCGWINSZ, addr win)
  discard posix.close(fd)
  if res == -1:
    return

  COLS = max(cint(win.ws_col), 10)
  LINES = max(cint(win.ws_row), 10)

  resizeterm(LINES, COLS)
  if wresize(stdscr, LINES, COLS) == ERR:
    die("Cannot resize window!")

  varInit()
  # Do these because width may have changed...
  clearScreen()
  refresh()

proc parseColor(name: string): cshort =
  case name.toLowerAscii
  of "green": COLOR_GREEN
  of "red": COLOR_RED
  of "blue": COLOR_BLUE
  of "white": COLOR_WHITE
  of "yellow": COLOR_YELLOW
  of "cyan": COLOR_CYAN
  of "magenta": COLOR_MAGENTA
  of "black": COLOR_BLACK
  else:
    die(" Invalid color selection\n Valid colors are green, red, blue, " &
        "white, yellow, cyan, magenta and black.\n")
    COLOR_GREEN

proc main() =
  var
    count = 0
    screensaver = false
    asynch = false
    bold = 0
    force = false
    oldstyle = false
    update = 4
    mcolor = COLOR_GREEN
    rainbow = false
    lambda = false
    pause = false
    classic = false
    changes = false
    msg = ""
    tty = ""

  randomize()
  discard setlocale(LC_ALL, "")

  # getopt-style parsing of "abBcfhlLnrosmxkVM:u:C:t:"
  let args = commandLineParams()
  var ai = 0
  while ai < args.len:
    let arg = args[ai]
    inc ai
    if arg == "--":
      break
    if arg.len < 2 or arg[0] != '-':
      continue
    var ci = 1
    while ci < arg.len:
      let opt = arg[ci]
      inc ci
      var optarg = ""
      if opt in {'M', 'u', 'C', 't'}:
        if ci < arg.len:
          optarg = arg[ci .. ^1]
          ci = arg.len
        elif ai < args.len:
          optarg = args[ai]
          inc ai
        else:
          usage()
          quit(0)
      case opt
      of 's': screensaver = true
      of 'a': asynch = true
      of 'b':
        if bold != 2: bold = 1
      of 'B': bold = 2
      of 'C': mcolor = parseColor(optarg)
      of 'c': classic = true
      of 'P':
        classic = true
        pixelKana = true
      of 'f': force = true
      of 'l': console = true
      of 'L':
        lock = true
        # if -M was used earlier, don't override it
        if msg.len == 0:
          msg = "Computer locked."
      of 'M': msg = optarg
      of 'n': bold = -1
      of 'o': oldstyle = true
      of 'u': update = (try: parseInt(optarg) except ValueError: 0)
      of 'x': xwindow = true
      of 'V':
        version()
        quit(0)
      of 'r': rainbow = true
      of 'm': lambda = true
      of 'k': changes = true
      of 't': tty = optarg
      else:
        usage()
        quit(0)

  if force and getEnv("TERM") != "linux":
    putEnv("TERM", "linux")

  var outFd: cint = STDOUT_FILENO
  if tty.len > 0:
    var ftty: File
    if not open(ftty, tty, fmReadWriteExisting):
      stderr.writeLine("cmatrix-nim: error: '", tty, "' couldn't be opened: ",
                       $strerror(errno), ".")
      quit(QuitFailure)
    let ttyscr = newterm(nil, ftty, ftty)
    if ttyscr == nil:
      quit(QuitFailure)
    discard set_term(ttyscr)
    outFd = getFileHandle(ftty)
  else:
    discard initscr()
  if console and not isLinuxConsole(outFd):
    # -l swaps the console font, which only works on a Linux VT. Run in
    # normal mode instead and say why once the screen is restored.
    console = false
    consoleNotice = "cmatrix-nim: -l needs a Linux virtual console (Ctrl+Alt+F3 etc.); " &
                    "ran in normal mode instead."
  savetty()
  nonl()
  cbreak()
  noecho()
  timeout(0)
  leaveok(stdscr, true)
  curs_set(0)
  for s in [SIGINT, SIGQUIT, SIGWINCH, SIGTSTP]:
    discard signal(s, sighandler)

  if console:
    case fontCommand()
    of "consolechars":
      if execCmd("consolechars -f matrix") != 0:
        die(" There was an error running consolechars. Please make sure the\n" &
            " consolechars program is in your $PATH.  Try running \"consolechars -f matrix\" by hand.\n")
    of "setfont":
      if execCmd("setfont matrix") != 0:
        die(" There was an error running setfont. Please make sure the\n" &
            " setfont program is in your $PATH.  Try running \"setfont matrix\" by hand.\n")
    else:
      die(" Unable to use both \"setfont\" and \"consolechars\".\n")

  if has_colors():
    start_color()
    # Add in colors, if available
    let bg: cshort = if use_default_colors() != ERR: -1 else: COLOR_BLACK
    init_pair(COLOR_BLACK, if bg == -1: -1 else: COLOR_BLACK, bg)
    for c in [COLOR_GREEN, COLOR_WHITE, COLOR_RED, COLOR_CYAN,
              COLOR_MAGENTA, COLOR_BLUE, COLOR_YELLOW]:
      init_pair(c, c, bg)

  # Set up values for random number generation
  var randmin, highnum: int
  if classic:
    # Half-width kana characters. In the movie they are y-axis flipped, and
    # they appear alongside latin characters and numerals, but this is the
    # closest we can do with a standard unicode set and a single number range
    randmin = 0xff66
    highnum = 0xff9d
  elif console or xwindow:
    randmin = 166
    highnum = 217
  else:
    randmin = 33
    highnum = 123
  let randnum = highnum - randmin
  proc randChar(): int = rnd(randnum) + randmin

  if pixelKana:
    buildKanaCells()
  varInit()

  while true:
    # Check for signals
    if signalStatus == SIGINT or signalStatus == SIGQUIT:
      if not lock:
        finish()
    if signalStatus == SIGWINCH:
      resizeScreen()
      signalStatus = 0
    if signalStatus == SIGTSTP:
      if not lock:
        finish()

    inc count
    if count > 4:
      count = 1

    let keypress = int(wgetch(stdscr))
    if keypress != ERR:
      if screensaver:
        finish()
      else:
        case keypress
        of ord('q'):
          if not lock: finish()
        of ord('a'): asynch = not asynch
        of ord('b'): bold = 1
        of ord('B'): bold = 2
        of ord('L'): lock = true
        of ord('n'): bold = 0
        of ord('0') .. ord('9'): update = keypress - ord('0')
        of ord('!'): mcolor = COLOR_RED; rainbow = false
        of ord('@'): mcolor = COLOR_GREEN; rainbow = false
        of ord('#'): mcolor = COLOR_YELLOW; rainbow = false
        of ord('$'): mcolor = COLOR_BLUE; rainbow = false
        of ord('%'): mcolor = COLOR_MAGENTA; rainbow = false
        of ord('r'): rainbow = true
        of ord('m'): lambda = not lambda
        of ord('^'): mcolor = COLOR_CYAN; rainbow = false
        of ord('&'): mcolor = COLOR_WHITE; rainbow = false
        of ord('p'), ord('P'): pause = not pause
        else: discard

    let lines = gridLines()
    let cols = gridCols()
    for j in countup(0, cols - 1, 2):
      if (count > updates[j] or not asynch) and not pause:
        # I don't like old-style scrolling, yuck
        if oldstyle:
          for i in countdown(lines - 1, 1):
            matrix[i][j].val = matrix[i - 1][j].val
          let random = rnd(randnum + 8) + randmin

          if matrix[1][j].val == 0:
            matrix[0][j].val = 1
          elif matrix[1][j].val == ord(' ') or matrix[1][j].val == -1:
            if spaces[j] > 0:
              matrix[0][j].val = ord(' ')
              dec spaces[j]
            else:
              # Random number to determine whether head of next column
              # of chars has a white 'head' on it.
              if rnd(3) == 1:
                matrix[0][j].val = 0
              else:
                matrix[0][j].val = randChar()
              spaces[j] = rnd(lines) + 1
          elif random > highnum and matrix[1][j].val != 1:
            matrix[0][j].val = ord(' ')
          else:
            matrix[0][j].val = randChar()

        else: # New style scrolling (default)
          if matrix[0][j].val == -1 and matrix[1][j].val == ord(' ') and spaces[j] > 0:
            dec spaces[j]
          elif matrix[0][j].val == -1 and matrix[1][j].val == ord(' '):
            length[j] = rnd(lines - 3) + 3
            matrix[0][j].val = randChar()
            spaces[j] = rnd(lines) + 1
          var i = 0
          var firstcoldone = false
          while i <= lines:
            # Skip over spaces
            while i <= lines and (matrix[i][j].val == ord(' ') or matrix[i][j].val == -1):
              inc i
            if i > lines:
              break

            # Go to the head of this column
            let z = i
            var y = 0
            while i <= lines and (matrix[i][j].val != ord(' ') and matrix[i][j].val != -1):
              matrix[i][j].isHead = false
              if changes and rnd(8) == 0:
                matrix[i][j].val = randChar()
              inc i
              inc y

            if i > lines:
              matrix[z][j].val = ord(' ')
              continue

            matrix[i][j].val = randChar()
            matrix[i][j].isHead = true

            # If we're at the top of the column and it's reached its full
            # length (about to start moving down), we do this to get it
            # moving. This is also how we keep segments not already growing
            # from growing accidentally.
            if y > length[j] or firstcoldone:
              matrix[z][j].val = ord(' ')
              matrix[0][j].val = -1
            firstcoldone = true
            inc i

      # A simple hack
      let (y0, z0) = if not oldstyle: (1, lines) else: (0, lines - 1)
      for i in y0 .. z0:
        let row = i - y0
        let x = screenX(j)
        let cell = matrix[i][j]

        if cell.val == 0 or (cell.isHead and not rainbow):
          if console or xwindow: attron(A_ALTCHARSET)
          attron(COLOR_PAIR(cint(COLOR_WHITE)))
          if bold != 0: attron(A_BOLD)
          if cell.val == 0:
            if console or xwindow:
              moveTo(cint(row), x)
              addch(183)
            else: emit(row, x, 0, "&")
          elif cell.val == -1:
            emit(row, x, -1, " ")
          else:
            emit(row, x, cell.val, $Rune(cell.val))
          attroff(COLOR_PAIR(cint(COLOR_WHITE)))
          if bold != 0: attroff(A_BOLD)
          if console or xwindow: attroff(A_ALTCHARSET)
        else:
          if rainbow:
            mcolor = [COLOR_GREEN, COLOR_BLUE, COLOR_BLACK, COLOR_YELLOW,
                      COLOR_CYAN, COLOR_MAGENTA][rnd(6)]
          attron(COLOR_PAIR(cint(mcolor)))
          if cell.val == 1:
            if bold != 0: attron(A_BOLD)
            emit(row, x, 1, "|")
            if bold != 0: attroff(A_BOLD)
          else:
            if console or xwindow: attron(A_ALTCHARSET)
            let isBold = bold == 2 or (bold == 1 and cell.val mod 2 == 0)
            if isBold: attron(A_BOLD)
            if cell.val == -1:
              emit(row, x, -1, " ")
            elif lambda and cell.val != ord(' '):
              emit(row, x, -2, "λ")
            else:
              emit(row, x, cell.val, $Rune(cell.val))
            if isBold: attroff(A_BOLD)
            if console or xwindow: attroff(A_ALTCHARSET)
          attroff(COLOR_PAIR(cint(mcolor)))

    # check if -M and/or -L was used
    if msg.len > 0:
      # Add our message to the screen
      let msgX = LINES div 2
      let msgY = cint(int(COLS) div 2 - msg.len div 2)
      let pad = repeat(' ', msg.len + 4)

      moveTo(msgX - 1, msgY - 2)
      addstr(cstring(pad))
      moveTo(msgX, msgY - 2)
      addstr(cstring("  " & msg & "  "))
      moveTo(msgX + 1, msgY - 2)
      addstr(cstring(pad))

    napms(cint(update * 10))

when isMainModule:
  main()
