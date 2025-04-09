# Package

version = "0.1.0"
author = "Jacek Sieka"
description = "A new awesome nimble package"
license = "MIT"
srcDir = "src"
bin = @["nora"]

# Dependencies

requires "nim >= 2.0.12",
  "web3",
  "https://github.com/seaqt/nim-seaqt.git#c6288110986a0d4241157484269fe87000e666c3",
  "stew"
