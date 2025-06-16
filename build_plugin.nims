mode = ScriptMode.Verbose

import std.os

# Project constants
const
  ModuleName = "Nora"
  PluginSourceFile = "src/nora.nim"

task qml_plugin_build, "Building nora lib as a qml plugin":
  let
    workspaceDir = getCurrentDir()
    nimCmd = &"nim c --app:lib -d:moduleName=\"{ModuleName}\" " &
      &"--outdir:\"{workspaceDir / \"build\" / ModuleName}\" " &
      &"\"{workspaceDir / PluginSourceFile}\""

  let result = gorgeEx(nimCmd)

  if result.exitCode != 0:
    echo "Command failed: ", nimCmd
    echo "Output: ", result.output

task qml_plugin_clean, "Clean plugin build":
  let workspaceDir = getCurrentDir()
  rmDir(workspaceDir / "build" / ModuleName)
