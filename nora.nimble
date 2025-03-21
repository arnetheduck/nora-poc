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
  "https://github.com/seaqt/nim-seaqt.git#522526740f3c6311164183344d18970a610ca842",
  "stew"
