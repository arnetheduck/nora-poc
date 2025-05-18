# Package

version = "0.1.0"
author = "Jacek Sieka"
description = "A new awesome nimble package"
license = "MIT"
srcDir = "src"
bin = @["nora"]

# Dependencies

requires "nim >= 2.0.12",
  "https://github.com/status-im/nim-web3.git#v0.5.0", #TODO: why the latest version fails to compile?
  "https://github.com/seaqt/nim-seaqt.git#qt-6.4",
  "https://github.com/alexjba/prl-to-pc.git",
  "stew"

# Include task scripts
include "setup_android.nims"
# include "deploy_android.nims"
include "deploy_android.nims"
