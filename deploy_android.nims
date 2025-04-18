mode = ScriptMode.Verbose

# Android deployment script for Nim+QML projects
import std/[os, strutils, strformat, json, tables, sets, sequtils]

type
  CpuPlatform = enum
    arm, arm64, i386, amd64

# Project constants
const
  AndroidApiVersion = 28
  AndroidMinSdkVersion = 21
  AndroidTargetSdkVersion = 28
  AndroidBuildToolsVersion = "35.0.1"
  AndroidCPUs = [arm64]
  ProjectName = "NoraApp"
  AppCompanyName = "nora"
  AppProductName = "noraapp"
  AppVersionCode = 1
  AppVersionName = "1.0"
  # Main Nim source file - using a simpler test file for Android
  ProjectSourceFile = "src/nora.nim"
  # QML resources directory
  QmlResourcesDir = "src/ui"
  # Build directory
  ProjectBuildPath = "android.build"

proc toAbiName(x: CpuPlatform): string =
  case x
    of arm: "armeabi-v7a"
    of arm64: "arm64-v8a"
    of i386: "x86"
    of amd64: "x86_64"

proc toTargetArch(x: CpuPlatform): string =
  case x
    of arm64: "aarch64-linux-android"
    of arm: "armv7a-linux-androideabi"
    of i386: "i686-linux-android"
    of amd64: "x86_64-linux-android"

# Helper function to run commands through our pkg-config interceptor
proc runWithPkgConfigInterceptor(cmd: string, arch: string = "arm64-v8a"): tuple[output: string, exitCode: int] =
  let 
    scriptDir = getCurrentDir()
    interceptor = scriptDir / "pkg-config-intercept.sh"
  
  # Ensure the interceptor script exists
  if not fileExists(interceptor):
    echo "Error: pkg-config interceptor script not found at: ", interceptor
    return (output: "Interceptor not found", exitCode: 1)
  
  # Make sure the script is executable
  discard staticExec("chmod +x " & interceptor)
  
  # Create a command that runs through our interceptor
  let fullCmd = "PKG_CONFIG_ARCH=" & arch & " " & interceptor & " " & cmd
  echo "Running command with pkg-config interceptor: ", fullCmd
  result = gorgeEx(fullCmd)
  
  if result.exitCode != 0:
    echo "Command failed: ", fullCmd
    echo "Output: ", result.output

when not declared(runCommand):
  proc runCommand(cmd: string): string =
    echo "Running: ", cmd
    let (output, exitCode) = gorgeEx(cmd)
    if exitCode != 0:
      echo "Command failed with exit code: ", exitCode
      echo "Output: ", output
      quit(1)
    elif output.len > 0:
      echo output
    
    return output

proc readEnvFile(): Table[string, string] =
  result = initTable[string, string]()
  
  if not fileExists(".env"):
    echo "Warning: .env file not found. Using environment variables instead."
    return
  
  for line in readFile(".env").splitLines():
    let line = line.strip()
    if line.len == 0 or line[0] == '#': continue
    
    let parts = line.split('=', 1)
    if parts.len == 2:
      let 
        key = parts[0].strip()
        value = parts[1].strip()
      
      result[key] = value

proc getEnvOrDefault(envVars: Table[string, string], key, default: string): string =
  if envVars.hasKey(key): 
    return envVars[key]
  
  # Check system environment as backup
  var value = getEnv(key)
  if value != "": 
    return value

  return default

proc checkEnvironment(): Table[string, string] =
  let envVars = readEnvFile()
  let requiredVars = ["JAVA_HOME", "ANDROID_SDK_ROOT", "ANDROID_NDK_ROOT", "QT_ROOT", "GRADLE_HOME", "QT_VERSION"]
  var missingVars: seq[string] = @[]
  
  for v in requiredVars:
    if not envVars.hasKey(v) and getEnv(v) == "":
      missingVars.add(v)
  
  if missingVars.len > 0:
    echo "Error: Missing environment variables: ", missingVars.join(", ")
    echo "Please make sure .env file exists with these variables defined or set them in your environment"
    quit(1)
  
  return envVars

proc getQtDir(cpu: CpuPlatform): string =
  let
    envVars = checkEnvironment()
    workspaceDir = getCurrentDir()
    qtRootEnv = getEnvOrDefault(envVars, "QT_ROOT", "android/tools/qt")
    qtVersion = getEnvOrDefault(envVars, "QT_VERSION", "5.15.2")

    qtDir = if isAbsolute(qtRootEnv):
              qtRootEnv
            else:
              workspaceDir / qtRootEnv

  var qtSuffix = ""
  if qtVersion.startsWith("6"):
    case cpu
      of arm64:
        qtSuffix = "_arm64_v8a"
      of arm:
        qtSuffix = "_armv7a"
      of i386:
        qtSuffix = "_x86"
      of amd64:
        qtSuffix = "_x86_64"

  result = qtDir / qtVersion / "android" & qtSuffix

task android_build, "Building nora lib":
  let
    envVars = checkEnvironment()
    workspaceDir = getCurrentDir()
    qtRootEnv = getEnvOrDefault(envVars, "QT_ROOT", "android/tools/qt")
    androidSdkEnv = getEnvOrDefault(envVars, "ANDROID_SDK_ROOT", "android/tools/sdk")
    androidNdkEnv = getEnvOrDefault(envVars, "ANDROID_NDK_ROOT", "android/tools/sdk/ndk/21.3.6528147")
    qtVersion = getEnvOrDefault(envVars, "QT_VERSION", "5.15.2")
    javaHomeEnv = getEnvOrDefault(envVars, "JAVA_HOME", "android/tools/jdk")
    qtMajor = qtVersion.split('.')[0]
  
  let
    androidNdk = if isAbsolute(androidNdkEnv):
                 androidNdkEnv
             else:
                 workspaceDir / androidNdkEnv
    androidSdk = if isAbsolute(androidSdkEnv):
                    androidSdkEnv
                else:
                    workspaceDir / androidSdkEnv
    hostPlatform = when defined(windows): 
                    "windows-x86_64"
                elif defined(macosx):
                    "darwin-x86_64" 
                else:
                    "linux-x86_64"
    javaHome = if isAbsolute(javaHomeEnv):
                javaHomeEnv
            else:
                workspaceDir / javaHomeEnv
  # Run androiddeployqt
  let
    targetQtBinPath = getQtDir(arm64) / "bin"
    hostQtBinPath = runCommand(targetQtBinPath & "/qmake -query QT_HOST_LIBEXECS")
    test = runCommand(hostQtBinPath & "/rcc -help") # check if rcc is available. Change the query above if rcc is not here
  # Generate proper pkgconfig files for Qt
  discard runCommand("prl_to_pc " & getQtDir(arm64) / "lib " & getQtDir(arm64) / "lib/pkgconfig " & getQtDir(arm64) & " " & hostQtBinPath)

  for cpu in AndroidCPUs:
    let
      archName = cpu.toAbiName
      targetArch = cpu.toTargetArch & $AndroidTargetSdkVersion
      toolchainPath = androidNdk / "toolchains/llvm/prebuilt" / hostPlatform
      toolchainBinPath = toolchainPath / "bin"
      clangOptions = "-fembed-bitcode -target " & targetArch & " --sysroot=" & toolchainPath / "sysroot"
      qtAndroidPath = getQtDir(cpu)
      qtPkgConfigPath = qtAndroidPath / "lib/pkgconfig"

    putEnv("PKG_CONFIG_PATH", qtPkgConfigPath)
    putEnv("QT_DIR", qtAndroidPath)

    echo "QT_DIR: ", qtAndroidPath
    echo "PKG_CONFIG_PATH: ", qtPkgConfigPath

    var currentPath = getEnv("PATH")
    if not currentPath.contains(toolchainBinPath):
      when defined(windows):
        putEnv("PATH", toolchainBinPath & ";" & currentPath)
      else:
        putEnv("PATH", toolchainBinPath & ":" & currentPath)

    let (ldFlags, exitCode) = runWithPkgConfigInterceptor("pkg-config --libs Qt" & qtMajor & "Gui", archName)

    let nimCmd = &"nim c -d:debug --app:lib --os:android -d:android --cpu:{$cpu} " &
                  &"-d:androidNDK " &
                  &"--cc:clang " &
                  &"--clang.path:\"{androidNdk}/toolchains/llvm/prebuilt/{hostPlatform}/bin\" " &
                  &"--clang.exe:\"{targetArch}-clang\" " &
                  &"--clang.linkerexe:\"{targetArch}-clang\" " &
                  &"--clang.options.always: \"-fembed-bitcode -target {targetArch} --sysroot={toolchainPath}/sysroot\" " &
                  &"--passL:\"{ldFlags}\" " &
                  &"-o:\"{workspaceDir / ProjectBuildPath / \"libs\" / archName / \"libnora_\" & archName & \".so\"}\" " &
                  &"\"{workspaceDir / ProjectSourceFile}\""

    discard runWithPkgConfigInterceptor(nimCmd, archName)

task android_deploy, "Deploy Android App":
  let
    envVars = checkEnvironment()
    workspaceDir = getCurrentDir()
    qtRootEnv = getEnvOrDefault(envVars, "QT_ROOT", "android/tools/qt")
    androidSdkEnv = getEnvOrDefault(envVars, "ANDROID_SDK_ROOT", "android/tools/sdk")
    androidNdkEnv = getEnvOrDefault(envVars, "ANDROID_NDK_ROOT", "android/tools/sdk/ndk/21.3.6528147")
    androidPlatform = getEnvOrDefault(envVars, "ANDROID_PLATFORM", "android-35")
    qtVersion = getEnvOrDefault(envVars, "QT_VERSION", "5.15.2")
    javaHomeEnv = getEnvOrDefault(envVars, "JAVA_HOME", "android/tools/jdk")
    qtMajor = qtVersion.split('.')[0]
    qtRoot = if isAbsolute(qtRootEnv):
                 qtRootEnv 
             else: 
                workspaceDir / qtRootEnv
    androidNdk = if isAbsolute(androidNdkEnv):
                 androidNdkEnv
             else:
                 workspaceDir / androidNdkEnv
    androidSdk = if isAbsolute(androidSdkEnv):
                    androidSdkEnv
                else:
                    workspaceDir / androidSdkEnv
    javaHome = if isAbsolute(javaHomeEnv):
                javaHomeEnv
            else:
                workspaceDir / javaHomeEnv
    hostPlatform = when defined(windows): 
                "windows-x86_64"
            elif defined(macosx):
                "darwin-x86_64" 
            else:
                "linux-x86_64"
    qtAndroidPath = getQtDir(arm64)

  # Run androiddeployqt
  let
    targetQtBinPath = getQtDir(arm64) / "bin"
    hostQtBinPath = runCommand(targetQtBinPath & "/qmake -query QT_HOST_BINS")
  
  var hostQtLibexecPath = ""
  if qtMajor == "6":
    hostQtLibexecPath = runCommand(hostQtBinPath & "/qmake -query QT_HOST_LIBEXECS")
  else:
    hostQtLibexecPath = runCommand(hostQtBinPath & "/qmake -query QT_INSTALL_LIBEXECS")

  var currentPath = getEnv("PATH")
  when defined(windows):
    putEnv("PATH", targetQtBinPath & ";" & hostQtBinPath & ";" & hostQtLibexecPath & ";" & currentPath)
  else:
    putEnv("PATH", targetQtBinPath & ":" & hostQtBinPath & ":" & hostQtLibexecPath & ":" & currentPath)

  let configJson = %*{
    "qt": qtAndroidPath,
    "qtDataDirectory": ".",
    "qtLibExecsDirectory": "libexec",
    "qtLibsDirectory": "lib",
    "qtPluginsDirectory": "plugins",
    "qtQmlDirectory": "qml",
    "sdk": androidSdk,
    "sdkBuildToolsRevision": "35.0.1",
    "ndk": androidNdk,
    "toolchain-prefix": "llvm",
    "tool-prefix": "llvm",
    "rcc-binary": hostQtLibexecPath & "/rcc",
    "qml-importscanner-binary": hostQtLibexecPath & "/qmlimportscanner",
    "ndk-host": hostPlatform,
    "architectures": {"arm64-v8a":"aarch64-linux-android"},
    "android-min-sdk-version": "21",
    "android-target-sdk-version": "28",
    "qml-import-paths": workspaceDir / QmlResourcesDir,
    "qml-root-path": workspaceDir / "src",
    "stdcpp-path": androidNdk / "toolchains/llvm/prebuilt/" & hostPlatform & "/sysroot/usr/lib/",
    "qrcFiles": workspaceDir / "src/resources.qrc",
    "application-binary": "nora"
  }

  putEnv("JAVA_HOME", javaHome)

  # Write the config file
  let configPath = workspaceDir / ProjectBuildPath / "android-lib.config.json"
  writeFile(configPath, pretty(configJson))
  
  let deployCmd = &"androiddeployqt " &
                 &"--input {configPath} " &
                 &"--output {workspaceDir/ProjectBuildPath} " &
                 &"--android-platform {androidPlatform} " &
                 &"--jdk {javaHome} " &
                 &"--gradle " &
                 &"--reinstall " &
                 &"--verbose"
  
  discard runCommand(deployCmd)

task android_run, "Building and running nora":
  let
    workspaceDir = getCurrentDir()
    envVars = checkEnvironment()
    androidSdk = getEnvOrDefault(envVars, "ANDROID_SDK_ROOT", "android/tools/sdk")
    platformToolsPath = if isAbsolute(androidSdk):
                          androidSdk / "platform-tools/"
                       else:
                          workspaceDir / androidSdk / "platform-tools/"
    qtMajor = getEnvOrDefault(envVars, "QT_VERSION", "6.8.3").split('.')[0]
    activityName = "org.qtproject.example.nora/org.qtproject.qt" & (if qtMajor == "5": "5" else: "") & ".android.bindings.QtActivity"
  android_buildTask()
  android_deployTask()
  discard runCommand(platformToolsPath & "adb logcat -c")
  discard runCommand(platformToolsPath & "adb shell am start -n " & activityName & " &")

task android_clean, "Clean Android build":
  let
    workspaceDir = getCurrentDir()
  rmDir(workspaceDir / ProjectBuildPath)
  rmFile(workspaceDir & "/src/resources.cpp")
