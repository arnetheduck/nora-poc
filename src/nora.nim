import
  std/[json, macros, os, sequtils, strutils],
  web3,
  chronicles,
  json_rpc/[client, private/jrpc_sys],
  chronos,
  ./[apicalls, threadchannel]

import
  seaqt/[
    qapplication, qabstractlistmodel, qabstracttablemodel, qqmlapplicationengine,
    qqmlcontext, qurl, qobject, qvariant, qmetatype, qmetaproperty, qstringlistmodel,
  ],
  seaqt/QtCore/[gen_qnamespace, qtcore_pkg],
  ./nimside

func gorgeOrFail(cmd: string): string {.compileTime.} =
  let (output, exitCode) = gorgeEx(cmd)
  if exitCode != 0:
    error(output)
  output

func findRcc(): string {.compileTime.} =
  let
    qtMajor = QtCoreGenVersion.split(".")[0]
    vars = gorgeOrFail("pkg-config --print-variables Qt" & qtMajor & "Core")
    # On android, we need host_bins it seems? TODO..
    dir = if "host_bins" in vars: "host_bins" else: "libexecdir"
  gorgeOrFail("pkg-config --variable=" & dir & " Qt" & qtMajor & "Core") & "/rcc"

const
  curPath = currentSourcePath.parentDir
  qtMajor = QtCoreGenVersion.split(".")[0]
  rccPath = findRcc()
  cflags = gorgeOrFail("pkg-config --cflags Qt" & qtMajor & "Core")

when defined(gcc) or defined(clang):
  # TODO work around some functions becoming const in newer qt versions which
  #      messes up seaqt
  {.passC: "-fpermissive".}

static:
  discard gorgeOrFail(
    rccPath & " " & curPath & "/resources.qrc -no-zstd  -o " & curPath & "/resources.cpp"
  )
{.compile(curPath & "/resources.cpp", cflags).}

# Simple inheritance from QAbstractItemModel - since we're not exposing any
# new signals / slots, we don't really need qobject here
type ParamsList = ref object of VirtualQAbstractTableModel
  api: CallSig
  values: seq[string]

proc init(_: type ParamsList, api: CallSig): ParamsList =
  let ret = ParamsList(api: api, values: api.params.mapIt(it.def))
  QAbstractTableModel.create(ret)
  ret

method rowCount*(self: ParamsList, parent: QModelIndex): cint =
  cint self.api.params.len

method columnCount*(self: ParamsList, parent: QModelIndex): cint =
  3

method data*(self: ParamsList, index: QModelIndex, role: cint): QVariant =
  let row = index.row()
  case index.column
  of 0:
    QVariant.create(self.api.params[row].name)
  of 1:
    QVariant.create(self.api.params[row].typ)
  of 2:
    QVariant.create(self.values[row])
  else:
    QVariant.create()

method flags*(self: ParamsList, index: QModelIndex): cint =
  if index.column() == 2:
    ItemFlagEnum.ItemIsSelectable or ItemFlagEnum.ItemIsEnabled or
      ItemFlagEnum.ItemIsEditable
  else:
    ItemFlagEnum.ItemIsSelectable or ItemFlagEnum.ItemIsEnabled

method setData*(
    self: ParamsList, index: QModelIndex, value: QVariant, role: cint
): bool =
  if index.column == 2:
    self.values[index.row()] = value.toString()
    self[].dataChanged(index, index, [role])
    true
  else:
    false

type Request = object
  url: string
  name: string
  params: RequestParamsTx

qobject:
  type WorkerObject = ref object of VirtualQObject
    ## QObject with signal used as a thread-safe channel to send messages from
    ## the chronos worker thread to the UI thread

  proc respond(self: WorkerObject, res: string) {.signal, raises: [], gcsafe.}

proc callWeb3(
    url, name: string, params: RequestParamsTx
): Future[string] {.async: (raises: [CancelledError]).} =
  try:
    let web3 = await newWeb3(url)
    defer:
      discard web3.provider.close()

    let x = await web3.provider.call(name, params)
    JrpcConv.encode(parseJson(string(x)), pretty = true)
  except CancelledError as exc:
    raise exc
  except CatchableError as exc:
    exc.msg

type
  ApiChannel = ThreadChannel[Request]
  WorkerObjectPtr = typeof(addr WorkerObject()[])
  ThreadArg = tuple[chan: ptr ApiChannel, responder: WorkerObjectPtr]

proc processOne(
    chan: ptr ApiChannel, responder: WorkerObjectPtr
): Future[bool] {.async: (raises: []).} =
  try:
    let req = await chan.recv()
    if req.name.len == 0:
      return false

    let resp = await callWeb3(req.url, req.name, req.params)
    responder.respond(resp)
  except CancelledError as exc:
    return false
  except CatchableError as exc:
    echo exc.getStackTrace()

  true

proc chronosThread(arg: ThreadArg) {.thread, raises: [].} =
  notice "Starting chronos loop"

  while waitFor processOne(arg.chan, arg.responder):
    discard

  notice "Stopped chronos loop"

qobject:
  type MainModel = ref object of VirtualQObject
    urls {.qproperty(write = false, notify = false).}: QStringListModel
    url {.qproperty.}: string
    apiNames* {.qproperty(write = false, notify = false).}: seq[string]
    response* {.qproperty.}: string
    api* {.qproperty.}: string
    params {.qproperty(write = false).}: ParamsList

    inflight {.qproperty.}: int

    worker: WorkerObject
    chan: ApiChannel

  proc run(m: MainModel) {.slot, raises: [].} =
    m.setResponse:
      if m.params == nil:
        "No params"
      else:
        try:
          let params = RequestParamsTx(
            kind: rpPositional,
            positional:
              m.params.api.params.zip(m.params.values).mapIt(it[0].encode(it[1])),
          )

          if not m.chan.trySend(
            Request(url: m.url, name: m.params.api.name, params: params)
          ):
            "Could not send params"
          else:
            m.setInflight(m.inflight + 1)

            "Calling " & m.url & " " & m.params.api.name & "\n" &
              JrpcSys.encode(params, pretty = true)
        except CatchableError as exc:
          "Can't encode request: " & exc.msg

proc initApp(uri: string) =
  let
    _ = QApplication.create()
    main = MainModel(
      urls: QStringListModel.create([uri]), url: uri, apiNames: apiList.mapIt(it.name)
    )
    engine = QQmlApplicationEngine.create()

  main.params = ParamsList.init(apiList[0])
  main.worker = WorkerObject()
  main.worker.setup()

  main.worker.onRespond proc(v: string) =
    main.setInflight(main.inflight - 1)
    main.setResponse(v)

  main.setup()

  main.onApiChanged proc() =
    if main.params == nil or main.params.api.name != main.api:
      for x in apiList:
        if x.name == main.api:
          main.params = ParamsList.init(x)
          main.paramsChanged()
          break

  main.chan.open()

  var ct: Thread[ThreadArg]
  createThread(ct, chronosThread, (addr main.chan, addr main.worker[]))

  engine.rootContext().setContextProperty("main", main[])

  engine.addImportPath("qrc:/")
  engine.load(QUrl.create("qrc:/ui/main.qml"))
  # engine.load(QUrl.create("file://home/arnetheduck/status/nora/src/ui/main.qml"))

  discard QApplication.exec()

  discard main.chan.trySend(default(Request))
  ct.joinThread()

  main.chan.close()

when appType == "lib" or appType == "staticlib":
  proc NimMain() {.importc.}
  proc main(): cint {.exportc, dynlib, cdecl.} =
    NimMain() # Initialize Nim runtime first
    initApp("http://localhost:8545")
    return 0

when isMainModule and appType != "lib" and appType != "staticlib":
  initApp("http://localhost:8545")
