# Package

version       = "2.3.0"
author        = "Chris Allegretta, Abishek V Ashok (original cmatrix); Nim port contributors"
description   = "Terminal based 'The Matrix' like screen saver, ported to Nim"
license       = "GPL-3.0-or-later"
srcDir        = "src"
namedBin      = {"cmatrix_nim": "cmatrix-nim"}.toTable()

# Dependencies

requires "nim >= 2.0.0"

# Needs the ncursesw library and headers (e.g. libncurses-dev or conda-forge ncurses).
