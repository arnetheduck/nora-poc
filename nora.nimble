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
  "https://github.com/alexjba/nim-seaqt.git#qt-6.4-android",
  "https://github.com/alexjba/prl-to-pc.git",
  "stew"

# Include task scripts
include "setup_android.nims"
# include "deploy_android.nims"
include "deploy_android.nims"