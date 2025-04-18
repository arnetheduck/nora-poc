import std/[strutils, json, os, uri, sets, tables, sequtils]

proc runCommand(cmd: string): string =
  echo "Running: ", cmd
  let (output, exitCode) = gorgeEx(cmd)
  if exitCode != 0:
    quit("Command execution failed: " & cmd)
  else:
    if output.len > 0:
      echo output
  return output

proc ensureDirExists(path: string) =
  if not dirExists(path):
    try:
      var mkdirCmd = ""
      when defined(windows):
        mkdirCmd = "mkdir " & quoteShell(path)
      else:
        mkdirCmd = "mkdir -p " & quoteShell(path)
      
      discard runCommand(mkdirCmd)
    except CatchableError as e:
      quit("Failed to create directory " & path & ": " & e.msg)

proc downloadFile(url, destFile: string) =
  echo "Downloading " & url.split("/")[^1] & "..."
  
  var downloadCmd = ""
  if findExe("curl") != "":
    downloadCmd = "curl -L -s -o " & quoteShell(destFile) & " " & quoteShell(url)
  elif findExe("wget") != "":
    downloadCmd = "wget -q -O " & quoteShell(destFile) & " " & quoteShell(url)
  else:
    quit("Error: Neither curl nor wget found. Please install one of them to continue.")
  
  try:
    discard runCommand(downloadCmd)
  except CatchableError as e:
    quit("Failed to download file: " & e.msg)

proc extractZip(zipFile, destDir: string) =
  echo "Extracting " & zipFile.split("/")[^1] & "..."
  let ext = zipFile.split(".")[^1]
  var extractcmd: string
  if ext == "zip":
    extractCmd = "unzip -q -o " & quoteShell(zipFile) & " -d " & quoteShell(destDir)
  elif ext == "7z":
    extractCmd = "7z x " & quoteShell(zipFile) & " -o" & quoteShell(destDir)
  elif ext == "gz":
    extractCmd = "tar -xf " & quoteShell(zipFile) & " -C " & quoteShell(destDir)
  else:
    quit("Cannot extract file: " & zipFile)

  try:
    discard runCommand(extractCmd)
  except CatchableError as e:
    quit("Failed to extract file: " & e.msg)

proc removeDirRecursive(path: string) =
  if not dirExists(path):
    return
    
  var rmCmd = ""
  when defined(windows):
    rmCmd = "rmdir /s /q " & quoteShell(path)
  else:
    rmCmd = "rm -r " & quoteShell(path)
  
  try:
    discard runCommand(rmCmd)
  except CatchableError as e:
    echo "Warning: Failed to remove directory: " & e.msg

proc moveDirCommand(src, dest: string) =
  var mvCmd = ""
  when defined(windows):
    mvCmd = "move " & quoteShell(src) & " " & quoteShell(dest)
  else:
    mvCmd = "mv " & quoteShell(src) & " " & quoteShell(dest)
  
  try:
    discard runCommand(mvCmd)
  except CatchableError as e:
    quit("Failed to move directory: " & e.msg)

proc removeFileCommand(path: string) =
  # First check if the file exists
  if not fileExists(path):
    return
    
  var rmCmd = ""
  when defined(windows):
    rmCmd = "del " & quoteShell(path)
  else:
    rmCmd = "rm " & quoteShell(path)
  
  try:
    discard runCommand(rmCmd)
  except CatchableError as e:
    echo "Warning: Failed to remove file: " & e.msg

task install_qt, "Creates directories and installs Qt for Android using aqt":
  # Read configuration from JSON file
  echo "Setting up Qt for Android..."

  # Parse the JSON config file
  let 
    configJson = readFile("android-tools.json")
    config = parseJson(configJson)
    qtRoot = config["paths"]["qt_root"].getStr("android/tools/qt")
    qtVersion = config["qt"]["version"].getStr("5.15.2")
    qtAndroidDir = qtRoot / qtVersion / "android"
    qmakePath = qtAndroidDir / "bin" / "qmake"
  
  if fileExists(qmakePath):
    echo "Qt for Android already installed at: " & qtAndroidDir
    return

  # Determine OS for aqt command
  var osName: string
  when defined(windows):
    osName = "windows"
  elif defined(linux):
    osName = "linux"
  elif defined(osx):
    osName = "mac"
  else:
    quit("Unsupported platform for Qt installation")

  ensureDirExists(qtRoot)

  var cmdPrefix = ""
  when defined(osx) and defined(arm64):
    # Use Rosetta 2 via 'arch -x86_64' on macOS ARM
    cmdPrefix = "arch -x86_64 "
  
  echo "Installing Qt for Android...Have a seat, this will take a while..."

  if qtVersion.startsWith("5"):
    var aqtCmd = cmdPrefix & "aqt install-qt -O " & qtRoot & " " & osName & " android " & qtVersion

    discard runCommand(aqtCmd)
    echo "Qt installation completed."
    return

  if qtVersion.startsWith("6"):
    echo "Qt6 for android depends on desktop Qt, installing it first..."
    var architectures = @["android_arm64_v8a", "android_armv7", "android_x86", "android_x86_64"]
    for arch in architectures:
      var aqtCmd = cmdPrefix & "aqt install-qt -O " & qtRoot & " " & osName & " android " & qtVersion & " " & arch & " --autodesktop"
      discard runCommand(aqtCmd)

task install_android_sdk_tools, "Installs/Updates Android SDK tools (cmdline, platform, build) using sdkmanager":
  echo "Installing Android SDK tools and components..."
  
  # 1. Parse the JSON config file
  let configJson = readFile("android-tools.json")
  let config = parseJson(configJson)
  let sdkRoot = config["paths"]["sdk_root"].getStr()
  let sdkVersion = config["sdk"]["version"].getStr()
  let components = config["sdk"]["components"]
  
  ensureDirExists(sdkRoot)
  
  let cmdlineToolsPath = sdkRoot / "cmdline-tools"
  let sdkManagerPath = cmdlineToolsPath / "bin" / "sdkmanager"
  
  var sdkManagerExists = false
  when defined(windows):
    sdkManagerExists = fileExists(sdkManagerPath & ".bat")
  else:
    sdkManagerExists = fileExists(sdkManagerPath)
  
  if not sdkManagerExists:
    echo "Android SDK Command-line tools not found. Downloading and installing..."
    var platformStr = ""
    let fileExt = "zip"
    
    when defined(windows):
      platformStr = "win"
    elif defined(linux):
      platformStr = "linux"
    elif defined(osx):
      platformStr = "mac"
    else:
      quit("Unsupported platform for Android SDK tools download")
    
    # Construct download URL for Command-line tools
    let cmdlineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-" & platformStr & "-9477386_latest." & fileExt
    let downloadPath = sdkRoot / ("commandlinetools-" & platformStr & "-latest." & fileExt)
    
    # Download command-line tools
    downloadFile(cmdlineToolsUrl, downloadPath)
    
    # Create extraction directory 
    ensureDirExists(sdkRoot)
    extractZip(downloadPath, sdkRoot)
    
    # Remove the downloaded zip file
    removeFileCommand(downloadPath)
    
    echo "Command-line tools installation complete."
  else:
    echo "Android SDK Command-line tools already installed."
  
  # 4. Install/Update the specified components using sdkmanager
  echo "Installing/Updating Android SDK components..."
  
  # SDK manager needs to know where the SDK is
  let sdkManagerEnv = "ANDROID_SDK_ROOT=" & sdkRoot
  
  # Accept licenses automatically
  echo "Accepting Android SDK licenses..."
  let acceptLicensesCmd = sdkManagerEnv & " " & sdkManagerPath & " --licenses --sdk_root=" & sdkRoot
  try:
    # Use echo to pipe "yes" to all prompts
    when defined(windows):
      let yesCmd = "echo y | " & acceptLicensesCmd
      discard runCommand(yesCmd)
    else:
      let yesCmd = "yes | " & acceptLicensesCmd
      discard runCommand(yesCmd)
  except:
    echo "Warning: Failed to accept licenses automatically. You may need to accept them manually."
  
  # Install each component from the configuration
  for component in components:
    let componentStr = component.getStr()
    echo "Installing component: " & componentStr
    
    let installCmd = sdkManagerEnv & " " & sdkManagerPath & " \"" & componentStr & "\" --sdk_root=" & sdkRoot
    try:
      # Automatically accept all prompts
      when defined(windows):
        let yesCmd = "echo y | " & installCmd
        discard runCommand(yesCmd)
      else:
        let yesCmd = "yes | " & installCmd
        discard runCommand(yesCmd)
    except:
      echo "Warning: Failed to install component: " & componentStr
  
  echo "Android SDK tools installation completed."

task generate_env_file, "Generates the .env file from android-tools.json":
  # Load configuration
  let configContent = readFile("android-tools.json")
  let config = parseJson(configContent)

  # Setup environment variables
  echo "Generating .env file..."
  let envFile = ".env"
  var envContent = ""

  # Add paths to environment
  let qtRoot = config["paths"]["qt_root"].getStr()
  let sdkRoot = config["paths"]["sdk_root"].getStr()
  let ndkRoot = config["paths"]["ndk_root"].getStr()
  let javaHome = config["paths"]["java_home"].getStr()
  let gradleHome = config["paths"]["gradle_home"].getStr()
  let qtVersion = config["qt"]["version"].getStr()
  let androidPlatform = config["sdk"]["platform"].getStr()
  let androidNdk = config["sdk"]["ndk"].getStr()

  envContent.add("ANDROID_SDK_ROOT=" & sdkRoot & "\n")
  envContent.add("ANDROID_NDK_ROOT=" & ndkRoot & "\n")
  envContent.add("QT_ROOT=" & qtRoot & "\n")
  envContent.add("JAVA_HOME=" & javaHome & "\n")
  envContent.add("GRADLE_HOME=" & gradleHome & "\n")
  envContent.add("QT_VERSION=" & qtVersion & "\n")
  envContent.add("ANDROID_PLATFORM=" & androidPlatform & "\n")
  envContent.add("ANDROID_NDK_VERSION=" & androidNdk & "\n")

  # Construct PATH with correct formatting
  let pathSeparator = ":"
  var pathContent = newSeq[string]()
  pathContent.add("$PATH")
  pathContent.add(sdkRoot / "platform-tools")
  pathContent.add(sdkRoot / "tools")
  pathContent.add(javaHome / "bin")
  pathContent.add(gradleHome / "bin")
  let qtBinPath = qtRoot / config["qt"]["version"].getStr() / "android" / "bin"
  pathContent.add(qtBinPath)

  envContent.add("PATH=" & pathContent.join(pathSeparator) & "\n")

  # Write environment file
  writeFile(envFile, envContent)
  echo "Environment variables written to ", envFile

task install_jdk, "Installs required JDK for Android development":
  echo "Setting up JDK for Android development..."
  
  # 1. Get Java configuration from android-tools.json
  let configJson = readFile("android-tools.json")
  let config = parseJson(configJson)
  let javaHome = config["paths"]["java_home"].getStr()
  let qtVersion = config["qt"]["version"].getStr()
  
  if javaHome == "": quit("Error: java_home path not found or empty in android-tools.json")
  
  # 2. Check if Java already exists
  let javaExecPath = javaHome / "bin" / "java"
  var javaExists = false
  
  when defined(windows):
    javaExists = fileExists(javaExecPath & ".exe")
  else:
    javaExists = fileExists(javaExecPath)
  
  if javaExists:
    echo "Java already installed at: " & javaExecPath
    
    # Additionally verify Java version is expected version
    try:
      let javaVersionCmd = javaExecPath & " -version"
      discard runCommand(javaVersionCmd)
      echo "Skipping JDK installation."
      return
    except:
      echo "Warning: Could not verify Java version. Will reinstall..."
      removeDirRecursive(javaHome)
  else:
    echo "Java not found. Will install JDK..."
  
  # 3. Ensure JDK directory exists
  ensureDirExists(javaHome.parentDir)
  
  # 4. Download and install JDK based on platform
  echo "Downloading and installing JDK.."
  
  # Determine platform-specific settings
  var platform, arch, fileExt, extractCmd: string
  
  when defined(windows):
    platform = "windows"
    fileExt = "zip"
    extractCmd = "unzip -q"
  elif defined(linux):
    platform = "linux"
    fileExt = "tar.gz"
    extractCmd = "tar -xzf"
  elif defined(osx):
    platform = "mac"
    fileExt = "tar.gz"
    extractCmd = "tar -xzf"
  else:
    platform = "linux"
    fileExt = "tar.gz"
    extractCmd = "tar -xzf"
    echo "Warning: Unsupported OS detected, defaulting to Linux."
  
  # Determine architecture
  when defined(amd64):
    arch = "x64"
  elif defined(i386):
    arch = "x86"
  else:
    arch = "x64" # Default to x64
  
  # Determine JDK version based on Qt version
  var jdkVersion, jdkBuild: string
  if qtVersion.startsWith("5"):
    jdkVersion = "11.0.21"
    jdkBuild = "9"
  else:
    jdkVersion = "17.0.10"
    jdkBuild = "7"
  
  # Construct download URL for Eclipse Temurin (AdoptOpenJDK)
  var jdkUrl = ""
  when defined(windows):
    jdkUrl = "https://github.com/adoptium/temurin" & jdkVersion.split('.')[0] & "-binaries/releases/download/jdk-" & jdkVersion & "%2B" & jdkBuild & "/OpenJDK" & jdkVersion.split('.')[0] & "U-jdk_x64_windows_hotspot_" & jdkVersion & "_" & jdkBuild & ".zip"
    fileExt = "zip"
  elif defined(linux):
    jdkUrl = "https://github.com/adoptium/temurin" & jdkVersion.split('.')[0] & "-binaries/releases/download/jdk-" & jdkVersion & "%2B" & jdkBuild & "/OpenJDK" & jdkVersion.split('.')[0] & "U-jdk_x64_linux_hotspot_" & jdkVersion & "_" & jdkBuild & ".tar.gz"
    fileExt = "tar.gz"
  elif defined(osx):
    jdkUrl = "https://github.com/adoptium/temurin" & jdkVersion.split('.')[0] & "-binaries/releases/download/jdk-" & jdkVersion & "%2B" & jdkBuild & "/OpenJDK" & jdkVersion.split('.')[0] & "U-jdk_x64_mac_hotspot_" & jdkVersion & "_" & jdkBuild & ".tar.gz"
    fileExt = "tar.gz"
  else:
    jdkUrl = "https://github.com/adoptium/temurin" & jdkVersion.split('.')[0] & "-binaries/releases/download/jdk-" & jdkVersion & "%2B" & jdkBuild & "/OpenJDK" & jdkVersion.split('.')[0] & "U-jdk_x64_linux_hotspot_" & jdkVersion & "_" & jdkBuild & ".tar.gz"
    fileExt = "tar.gz"
  
  let downloadPath = javaHome.parentDir / ("temurin-jdk" & jdkVersion & "_" & jdkBuild & "." & fileExt)
  
  # Ensure the download directory exists
  ensureDirExists(javaHome.parentDir)
  
  # Download JDK
  downloadFile(jdkUrl, downloadPath)
  extractZip(downloadPath, javaHome.parentDir)
  
  # Find the extracted JDK directory (it may have a version-specific name)
  var extractedDir = ""
  # Check for Temurin JDK extracted directory pattern
  for kind, path in walkDir(javaHome.parentDir):
    if kind == pcDir and (path.contains("jdk") or path.contains("openjdk")):
      extractedDir = path
      break
  
  # Handle macOS JDK structure which has Contents/Home subdirectories
  var srcDir = extractedDir
  when defined(osx):
    if dirExists(extractedDir / "Contents" / "Home"):
      srcDir = extractedDir / "Contents" / "Home"
      
  # Rename extracted directory to match expected javaHome
  if dirExists(srcDir) and srcDir != javaHome:
    # Create javaHome directory
    if not dirExists(javaHome):
      ensureDirExists(javaHome)
    else:
      removeDirRecursive(javaHome)
      ensureDirExists(javaHome)
    
    when defined(osx):
      # On macOS, copy contents of Home directory
      # Use shell glob expansion to copy
      for kind, path in walkDir(srcDir):
        let basename = path.splitPath().tail
        let targetPath = javaHome / basename
        let cpItemCmd = "cp -R " & quoteShell(path) & " " & quoteShell(targetPath)
        discard runCommand(cpItemCmd)

      # Cleanup
      removeDirRecursive(extractedDir)
    else:
      # On other platforms, move the directory
      moveDirCommand(srcDir, javaHome)
      
  # Verify java binary is now in place
  if fileExists(javaHome / "bin" / "java"):
    echo "JDK installation successful."
    discard runCommand(javaHome / "bin" / "java" & " -version")
  else:
    quit("Error: JDK installation failed. Java executable not found at expected location: " & javaHome / "bin" / "java")

  removeFileCommand(downloadPath)
  
task setup, "Complete Android development environment setup":
  echo "Starting complete Android development environment setup..."
  
  # 1. Install JDK
  echo "Step 1: Installing JDK..."
  exec "nim r " & currentSourcePath() & " install_jdk"
  
  # 2. Install Android SDK Tools
  echo "Step 3: Installing Android SDK Tools..."
  exec "nim r " & currentSourcePath() & " install_android_sdk_tools"
  
  # 4. Install Qt
  echo "Step 4: Installing Qt..."
  exec "nim r " & currentSourcePath() & " install_qt"
  
  # 5. Generate .env file
  echo "Step 5: Generating environment file..."
  exec "nim r " & currentSourcePath() & " generate_env_file"
  
  echo "Android development environment setup complete!"
  echo "To activate the environment, run: source .env"

proc getGradlePluginVersion(buildGradlePath: string): string =
  if not fileExists(buildGradlePath):
    quit("Error: build.gradle file not found in " & buildGradlePath)

  let buildGradleContent = readFile(buildGradlePath)
  let versionPrefix = "com.android.tools.build:gradle:"
  let startIndex = buildGradleContent.find(versionPrefix)
  if startIndex == -1:
    quit("Error: Could not find Android Gradle Plugin version ('" & versionPrefix & "') in build.gradle")
  
  let versionStart = startIndex + versionPrefix.len
  let endIndex = buildGradleContent.find({'\'', '"'}, versionStart)
  if endIndex == -1:
    quit("Error: Failed to parse build.gradle file")
    
  return buildGradleContent.substr(versionStart, endIndex - 1)
    

task install_gradle, "Installs the appropriate Gradle version based on build.gradle":
  # Step 1: Locate the build.gradle file and read config
  let
    configJson = readFile("android-tools.json")
    config = parseJson(configJson)
    qtRoot = config["paths"]["qt_root"].getStr("android/tools/qt")
    qtVersion = config["qt"]["version"].getStr("5.15.2")
    gradleHome = config["paths"]["gradle_home"].getStr("android/tools/gradle") 

  var defaultGradleFolder = ""
  if qtVersion.startsWith("5"):
    defaultGradleFolder = "android" / "src" / "android" / "templates"
  else:
    defaultGradleFolder = "android_arm64_v8a" / "src" / "android" / "templates"
    
  let  buildGradlePath = qtRoot / qtVersion / defaultGradleFolder / "build.gradle"
  # Check if the target Gradle version is already installed
  let gradleBinPath = gradleHome / "bin" / "gradle"
  var gradleExists = false
  when defined(windows):
      gradleExists = fileExists(gradleBinPath & ".bat")
  else:
      gradleExists = fileExists(gradleBinPath)

  if gradleExists:
    echo "Gradle already appears to be installed at: " & gradleHome & ". Skipping installation"
    return
  let pluginVersion = getGradlePluginVersion(buildGradlePath)
  var gradleVersion = ""
  if pluginVersion.startsWith("8."): # 8.0+ needs 8.0+
     gradleVersion = "8.0" # Or higher, let's pick a recent stable one like 8.6 if needed
  elif pluginVersion.startsWith("7.4."): # 7.4+ needs 7.5+
     gradleVersion = "7.5.1" 
  elif pluginVersion.startsWith("7.3."): # 7.3 needs 7.4+
     gradleVersion = "7.4.2"
  elif pluginVersion.startsWith("7.2."): # 7.2 needs 7.3.3+
     gradleVersion = "7.3.3"
  elif pluginVersion.startsWith("7.1."): # 7.1 needs 7.2+
     gradleVersion = "7.2"
  elif pluginVersion.startsWith("7.0."): # 7.0 needs 7.0.2+
     gradleVersion = "7.0.2"
  elif pluginVersion.startsWith("4.2."): # 4.2 needs 6.7.1+
     gradleVersion = "6.7.1"
  elif pluginVersion.startsWith("4.1."): # 4.1 needs 6.5+
     gradleVersion = "6.5.1" # Using 6.5.1 instead of 6.5
  elif pluginVersion.startsWith("4.0."): # 4.0 needs 6.1.1+
     gradleVersion = "6.1.1"
  elif pluginVersion.startsWith("3.6."): # 3.6 needs 5.6.4+
     gradleVersion = "5.6.4"
  elif pluginVersion.startsWith("3.5."): # 3.5 needs 5.4.1+
     gradleVersion = "5.4.1"
  # Add more mappings as needed
  else:
    echo "Warning: No specific compatible Gradle version found for AGP version " & pluginVersion & ". Defaulting to 6.7.1"
    gradleVersion = "6.7.1" # A somewhat safe default for older Qt versions

  let 
    gradleDistType = "bin" # Use "all" for sources/docs, "bin" for binary only
    gradleZipFileName = "gradle-" & gradleVersion & "-" & gradleDistType & ".zip"
    gradleUrl = "https://services.gradle.org/distributions/" & gradleZipFileName
    tempDir = gradleHome.parentDir / "gradle_temp"
    downloadPath = tempDir / gradleZipFileName
    extractDir = tempDir / "extract"

  removeDirRecursive(tempDir)
  ensureDirExists(tempDir)
  ensureDirExists(extractDir)

  echo "Downloading Gradle " & gradleVersion & " from " & gradleUrl & " to " & downloadPath
  downloadFile(gradleUrl, downloadPath)

  echo "Extracting Gradle to " & extractDir & "..."
  extractZip(downloadPath, extractDir)

  var extractedGradleRoot = ""
  for kind, path in walkDir(extractDir):
    if kind == pcDir and path.endsWith("gradle-" & gradleVersion):
      extractedGradleRoot = path
      break
  
  if extractedGradleRoot == "":
    quit("Error: Could not find extracted Gradle directory 'gradle-" & gradleVersion & "' in " & extractDir)

  # Move the contents to the final gradleHome
  echo "Moving extracted Gradle from " & extractedGradleRoot & " to " & gradleHome
  # Ensure target directory doesn't exist or is empty
  removeDirRecursive(gradleHome) 
  moveDirCommand(extractedGradleRoot, gradleHome)

  echo "Cleaning up temporary files..."
  removeDirRecursive(tempDir) # Removes downloadPath and extractDir

  # Final check to see if gradle binary exists AFTER installation attempt
  var gradleNowExists = false
  when defined(windows):
    gradleNowExists = fileExists(gradleBinPath & ".bat")
  else:
    gradleNowExists = fileExists(gradleBinPath)

  if gradleNowExists:
    echo "Gradle " & gradleVersion & " installed successfully in " & gradleHome 
  else:
    quit("Error: Gradle installation failed. Executable not found at " & gradleBinPath) 

task setup_android, "Installs Qt, Android SDK tools, JDK, Gradle, and generates the .env file":
  # This task delegates to tasks defined in setup_android.nims
  echo "--- Running Android Setup --- "
  install_qtTask()

  echo "Step 1/4: Installing Gradle (if needed)..."
  install_gradleTask()

  echo "Step 2/4: Installing Android SDK components (if needed)..."
  install_android_sdk_toolsTask()
  
  echo "Step 3/4: Installing JDK (if needed)..."
  install_jdkTask()
  
  echo "Step 4/4: Generating .env file..."
  generate_env_fileTask()
  echo "--- Android Setup Complete! --- "