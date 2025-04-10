import
  std/[json, os, sequtils],
  web3,
  json_rpc/[client, private/jrpc_sys],
  chronos,
  ./apicalls

import
  seaqt/[
    qapplication, qabstractlistmodel, qabstracttablemodel, qqmlapplicationengine,
    qqmlcontext, qurl, qobject, qvariant, qmetatype, qmetaproperty, qstringlistmodel,
    qeventloop,
  ],
  seaqt/QtCore/gen_qnamespace,
  ./nimside

const
  curPath = currentSourcePath.parentDir
  rccPath = gorge("pkg-config --variable=libexecdir Qt6Core") & "/rcc"
  cflags = gorge("pkg-config --cflags Qt6Core")

static:
  discard staticExec(
    rccPath & " " & curPath & "/resources.qrc -o " & curPath & "/resources.cpp"
  )
{.compile(curPath & "/resources.cpp", cflags).}

type ParamsList = ref object of VirtualQAbstractTableModel
  api: CallSig
  values: seq[string]

qobject:
  type MainModel = ref object of VirtualQObject
    urls {.qproperty(write = false, notify = false).}: QStringListModel
    url {.qproperty.}: string
    apiNames* {.qproperty(write = false, notify = false).}: seq[string]
    response* {.qproperty.}: string
    api* {.qproperty.}: string
    params {.qproperty(write = false).}: ParamsList

  proc run(m: MainModel) {.slot, raises: [].} =
    m.setResponse:
      if m.params == nil:
        "No params"
      else:
        try:
          let web3 = waitFor newWeb3(m.url)
          defer:
            discard
            # TODO crash on exception when this is enabled
            # discard web3.provider.close()

          let params = RequestParamsTx(
            kind: rpPositional,
            positional:
              m.params.api.params.zip(m.params.values).mapIt(it[0].encode(it[1])),
          )

          let x = waitFor web3.provider.call(m.params.api.name, params)
          JrpcConv.encode(parseJson(string(x)), pretty = true)
        except CatchableError as e:
          e.msg & "\n" & e.getStackTrace()

proc init(_: type ParamsList, api: CallSig): ParamsList =
  let ret = ParamsList(api: api, values: api.params.mapIt(it.def))
  QAbstractTableModel.create(ret)
  ret

method rowCount*(
    self: ParamsList, parent: gen_qabstractitemmodel_types.QModelIndex
): cint =
  cint self.api.params.len

method columnCount*(
    self: ParamsList, parent: gen_qabstractitemmodel_types.QModelIndex
): cint =
  3

method data*(
    self: ParamsList, index: gen_qabstractitemmodel_types.QModelIndex, role: cint
): gen_qvariant_types.QVariant =
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

method flags*(self: ParamsList, index: gen_qabstractitemmodel_types.QModelIndex): cint =
  debugEcho "flags ", index.column()
  if index.column() == 2:
    ItemFlagEnum.ItemIsSelectable or ItemFlagEnum.ItemIsEnabled or
      ItemFlagEnum.ItemIsEditable
  else:
    ItemFlagEnum.ItemIsSelectable or ItemFlagEnum.ItemIsEnabled

method setData*(
    self: ParamsList,
    index: gen_qabstractitemmodel_types.QModelIndex,
    value: gen_qvariant_types.QVariant,
    role: cint,
): bool =
  if index.column == 2:
    self.values[index.row()] = value.toString()
    self[].dataChanged(index, index, [role])
    true
  else:
    false

proc processUiEvents() {.async: (raises: []).} =
  # Ugly hack to process UI events while we're performing async work - sleepAsync
  # ensures it's only activated when a chronos loop is running
  var loop = QEventLoop.create()

  while true:
    await noCancel sleepAsync(millis(1000 div 60))
    loop.processEvents(QEventLoopProcessEventsFlagEnum.ExcludeUserInputEvents, 1)

proc main(uri: string) =
  let
    _ = QApplication.create()
    main = MainModel(
      urls: QStringListModel.create([uri]),
      url: uri,
      apiNames: apiList.mapIt(it.name),
    )
    engine = QQmlApplicationEngine.create()
  main.params = ParamsList.init(apiList[0])

  main.setup()

  engine.rootContext().setContextProperty("main", main[])

  engine.addImportPath("qrc:/")
  engine.load(QUrl.create("qrc:/ui/main.qml"))
  # engine.load(QUrl.create("file://home/arnetheduck/status/nora/src/ui/main.qml"))

  asyncSpawn processUiEvents()

  main.onApiChanged(
    proc() =
      if main.params() == nil or main.params().api.name != main.api:
        for x in apiList:
          if x.name == main.api:
            main.params = ParamsList.init(x)
            main.paramsChanged()
            break
  )
  discard QApplication.exec()

when isMainModule:
  main("http://localhost:8545")
