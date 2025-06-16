import std/[macros, compilesettings]

const
  QtQmlCFlags =
    gorge("pkg-config --cflags Qt6Qml") &
    (when defined(gcc) or defined(llvm): " -fPIC" else: "")

macro createDirAtCompileTime(dir: string): untyped =
  result = quote do:
    static:
      discard staticExec("mkdir -p " & `dir`)

macro writeFileAtCompileTime(filename: string, content: string): untyped =
  result = quote do:
    static:
      writeFile(`filename`, `content`)


func encodeCBORPluginMetaCxxArray(
  iid, className, uri: static[string]
): string =
  ## Based on https://codereview.qt-project.org/c/qt/qtbase/+/370750/5/src/tools/moc/generator.cpp#1571
  ## Basic plugin metadata encoder. Returns the C++ unsigned char array representation
  ## of the CBOR-encoded plugin metadata.
  const indent = "    "
  proc cborStringHeader(len: int): string =
    if len <= 23:
      result = "0x" & (0x60 + len).toHex(2) & ", "
    else:
      result = "0x78, 0x" & len.toHex(2) & ", "

  proc appendAscii(s: string, res: var string) =
    for i, c in s:
      res.add("'" & c & "', ")
      if (i + 1) mod 8 == 0 and i < s.high:
        res.add("\n" & indent)
    res.add("\n")

  proc appendComment(s: string, res: var string) =
    res.add(indent & "// \"" & s & "\"\n")

  var res = indent & "0xBF," & "\n"
  # IID
  appendComment("IID", res)
  res.add(indent & "0x02, ") # QtPluginMetaDataKeys::IID = 0x02
  res.add(cborStringHeader(iid.len) & "\n" & indent)
  appendAscii(iid, res)

  # className
  appendComment("className", res)
  res.add(indent & "0x03, ") # QtPluginMetaDataKeys::ClassName = 0x03
  res.add(cborStringHeader(className.len) & "\n" & indent)
  appendAscii(className, res)

  # "uri"
  appendComment("uri", res)
  res.add(indent & "0x63, 'u', 'r', 'i',\n" & indent & "0x81,\n" & indent)
  res.add(cborStringHeader(uri.len) & "\n" & indent)
  appendAscii(uri, res)
  res.add("\n" & indent & "0xff,\n")
  res

func generateCppMetadataHandlerCode(iid, className, uri: static[string]): string =
  """
#include <QtCore/qplugin.h>

static constexpr unsigned char qt_pluginMetaData[] = {
""" & encodeCBORPluginMetaCxxArray(iid, className, uri) & """

};

extern "C" Q_DECL_EXPORT QT_PREPEND_NAMESPACE(QPluginMetaData) qt_plugin_query_metadata_v2()
{
    static constexpr QT_PLUGIN_METADATAV2_SECTION QPluginMetaDataV2<qt_pluginMetaData> md{};
    return md;
}

"""

func generateQmldirContent(moduleName, libName: static[string]): string =
  "module " & moduleName & "\n" &
  "plugin " & libName


macro generatePlugin*(T: typed, moduleName, uri: string): untyped =
  result = quote do:
    const pluginDir = querySetting(SingleValueSetting.outDir)
    const nimcacheDir = querySetting(SingleValueSetting.nimcacheDir)
    const pluginRegistrationCppFile = nimcacheDir / "pluginRegistration.cpp"

    const iid = "org.qt-project.Qt.QQmlExtensionInterface/1.0"
    const cppContent = generateCppMetadataHandlerCode(iid, $(typeof(`T`)), `uri`)

    writeFileAtCompileTime(pluginRegistrationCppFile, cppContent)
    {.compile(pluginRegistrationCppFile, QtQmlCFlags)}

    createDirAtCompileTime(pluginDir)

    const projectName = querySetting(SingleValueSetting.projectName)
    const qmldirPath = pluginDir / "qmldir"
    const qmldirContent = generateQmldirContent(`moduleName`, projectName)

    writeFileAtCompileTime(qmldirPath, qmldirContent)

    let pluginSingleton = `T`()
    QQmlExtensionPlugin.create(pluginSingleton)

    proc qt_plugin_instance(): pointer {.exportc, dynlib, cdecl.} =
      return pluginSingleton.h
