import chronos, chronos/threadsync

export chronos

type ThreadChannel*[T] = object
  chan: Channel[T]
    # TODO We use a nim channel here to get to the object serialization it
    #      implements - convenient but certainly not optimal

  sig: ThreadSignalPtr

proc open*(tc: var ThreadChannel, maxItems = 0) =
  tc.sig = ThreadSignalPtr.new().expect("Free file descriptor for ThreadSignal")
  tc.chan.open(maxItems)

proc close*(tc: var ThreadChannel) =
  if tc.sig.isNil:
    return

  discard tc.sig.close()
  reset tc.sig

  tc.chan.close()

proc recv*[T](
    tc: ptr ThreadChannel[T]
): Future[T] {.async: (raises: [CancelledError]).} =
  while true:
    let (dataAvailable, msg) =
      try:
        tc[].chan.tryRecv()
      except ValueError as exc:
        raiseAssert exc.msg

    if dataAvailable:
      return msg

    try:
      await tc[].sig.wait()
    except AsyncError as exc:
      raiseAssert exc.msg

proc trySend*(tc: var ThreadChannel, msg: sink auto): bool =
  tc.chan.trySend(msg) and tc.sig.fireSync().expect("no errors")
