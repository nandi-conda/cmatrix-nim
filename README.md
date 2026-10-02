# cmatrix-nim

A Nim port of [cmatrix](https://github.com/abishekvashok/cmatrix), the terminal "The Matrix" screen saver.
It keeps cmatrix's options, key bindings and both scrolling modes, and talks to ncursesw directly.

## Install

From the [`nandi-testing`](https://prefix.dev/channels/nandi-testing) channel on prefix.dev:

```sh
pixi global install -c https://prefix.dev/nandi-testing -c conda-forge cmatrix-nim
# or
conda install -c https://prefix.dev/nandi-testing -c conda-forge cmatrix-nim
```

## Build from source

Needs Nim 2.x and ncursesw headers (`libncurses-dev` on Debian/Ubuntu).

```sh
nim c -d:release -o:cmatrix-nim src/cmatrix_nim.nim
./cmatrix-nim
```

Or build the conda package with `rattler-build build -r recipe.yaml -c conda-forge`.

## Usage

```
cmatrix-nim -[abBcHfhlsmPVxk] [-u delay] [-C color] [-t tty] [-M message]
```

Run `cmatrix-nim -h` for every flag.

`-c` prints real full-width katakana, two cells each, so your terminal needs a
font that covers them (e.g. Noto Sans Mono CJK JP). `-H` uses the half-width
katakana the C cmatrix prints instead; those are one cell wide, so most fonts
draw them as thin, squeezed glyphs. `-P` needs no CJK font: the katakana are
pre-rendered into the binary as 4x8 bitmaps (from GNU Unifont, mirrored like in
the film) and drawn with braille characters, two cells wide and two rows tall.
Regenerate them with `python3 tools/gen_kana.py`. While running: `q` quits, `0`-`9` set speed,
`!@#$%^&` change color, `r` rainbow, `m` lambda, `a` async, `b`/`B`/`n` bold, `p` pause.

Differences from the C version: the `-s` screensaver mode does not re-inject the
keystroke into the terminal (the C build only does so when compiled with `USE_TIOCSTI`),
and Windows is not supported.

## License

GPL-3.0-or-later, same as cmatrix. See `COPYING` and `AUTHORS`.
