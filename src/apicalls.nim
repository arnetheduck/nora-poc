import std/[macros, sequtils, strutils], web3/eth_api, stint, stew/byteutils

type
  ParamSig* = object
    name*: string
    typ*: string
    def*: string
    encode*: proc(s: string): JsonString {.raises: [CatchableError].}

  CallSig* = object
    name*: string
    ret*: string
    params*: seq[ParamSig]

template fromInput(_: type string, s: string): string =
  s

template fromInput(_: type BlockIdentifier, s: string): string =
  s

template fromInput[T: Address | Hash32](_: type T, s: string): T =
  T.fromHex(s)

template fromInput(_: type UInt256, s: string): UInt256 =
  if s.startsWith("0x"):
    parse(s, UInt256, 16)
  else:
    parse(s, UInt256)

template fromInput(_: type Quantity, s: string): Quantity =
  if s.startsWith("0x"):
    Quantity(fromHex[uint64](s))
  else:
    Quantity(parseBiggestUInt(s))

template fromInput(_: type seq[byte], s: string): seq[byte] =
  hexToSeqByte(s)

template paramDef(_: type bool): string =
  "true"
template paramDef(_: type string): string =
  ""
template paramDef(_: type BlockIdentifier): string =
  "latest"
template paramDef(_: type Address): string =
  $default(Address)
template paramDef(_: type Hash32): string =
  $default(Hash32)
template paramDef(_: type UInt256): string =
  $default(UInt256)
template paramDef(_: type Quantity): string =
  "0"
template paramDef(_: type seq[byte]): string =
  "0x"

template fromInput(_: type bool, s: string): bool =
  strip(toLowerAscii(s)) == "true"

template fromInput(_: type BlockIdentifier, s: string): string =
  s

template fromInput[T: Address | Hash32](_: type T, s: string): T =
  T.fromHex(s)

template fromInput(_: type UInt256, s: string): UInt256 =
  if s.startsWith("0x"):
    parse(s, UInt256, 16)
  else:
    parse(s, UInt256)

template fromInput(_: type Quantity, s: string): Quantity =
  if s.startsWith("0x"):
    Quantity(fromHex[uint64](s))
  else:
    Quantity(parseBiggestUInt(s))

template fromInput(_: type seq[byte], s: string): seq[byte] =
  hexToSeqByte(s)


func toJsonString(s: string, T: type): JsonString =
  JsonString JrpcConv.encode(T.fromInput(s))

proc decode(v: NimNode, o: NimNode) =
  if v.kind == nnkSym:
    let
      impl = getImpl(v)
      params = impl.params()

    if params.len > 1 and params[1][1].eqIdent("RpcClient"):
      let paramInit = nnkBracket.newTree(
        params[2 ..< params.len].mapIt(
          block:
            let
              pt = it[1]
              nameLit = newLit(repr(it[0]))
              typLit = newLit(repr(it[1]))
            quote:
              ParamSig(
                name: `nameLit`,
                typ: `typLit`,
                def: paramDef(type `pt`),
                encode: proc(s: string): JsonString =
                  toJsonString(s, type `pt`),
              )
        )
      )

      let name = newLit(repr(impl.name))
      o.add(
        quote do:
          CallSig(name: `name`, params: @(`paramInit`))
      )
    elif params.len >= 1 and params[1][1].eqIdent("RpcBatchCallRef"):
      discard
    else:
      debugEcho astGenRepr(params)
      error("Cannot parse signature", v)

macro toCallSig(v: varargs[typed]): array =
  var sigs = nnkBracket.newTree()

  for n in v: # varargs
    for nn in n: # nnkClosedSymChoice
      decode(nn, sigs)

  sigs

const apiList* = toCallSig(
  web3_clientVersion,
  web3_sha3,
  net_version,
  net_peerCount,
  net_listening,
  eth_protocolVersion,
  eth_syncing,
  eth_coinbase,
  eth_mining,
  eth_hashrate,
  eth_gasPrice,
  eth_blobBaseFee,
  eth_accounts,
  eth_blockNumber,
  eth_getBalance,
  eth_getStorageAt,
  eth_getTransactionCount,
  eth_getBlockTransactionCountByHash,
  eth_getBlockTransactionCountByNumber,
  eth_getBlockReceipts,
  eth_getUncleCountByBlockHash,
  eth_getUncleCountByBlockNumber,
  eth_getCode,
  eth_sign,
  # eth_signTransaction,
  # eth_sendTransaction,
  eth_sendRawTransaction,
  # eth_call,
  # eth_estimateGas,
  # eth_createAccessList,
  eth_getBlockByHash,
  eth_getBlockByNumber,
  eth_getTransactionByHash,
  eth_getTransactionByBlockHashAndIndex,
  eth_getTransactionByBlockNumberAndIndex,
  eth_getTransactionReceipt,
  eth_getUncleByBlockHashAndIndex,
  eth_getUncleByBlockNumberAndIndex,
  eth_getCompilers,
  eth_compileLLL,
  eth_compileSolidity,
  eth_compileSerpent,
  # eth_newFilter,
  eth_newBlockFilter,
  eth_newPendingTransactionFilter,
  eth_uninstallFilter,
  eth_getFilterChanges,
  eth_getFilterLogs,
  # eth_getLogs,
  eth_chainId,
  eth_getWork,
  # eth_submitWork,
  eth_submitHashrate,
  # eth_subscribe,
  eth_unsubscribe,
  # eth_getProof,

  # eth_feeHistory,
  debug_getRawBlock,
  debug_getRawHeader,
  debug_getRawReceipts,
  debug_getRawTransaction, # eth_getLogs,
)
