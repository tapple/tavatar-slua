Some Lua libraries for Second Life by Tapple Gao. The only thing here at the moment is ChatSocket

# ChatSocket
[ChatSocket](lib/ChatSocket.luau) is a high-level high-speed IO libray for sending bulk data between 2 prims on the same region, using `ll.RegionSayTo`. It implements flow control, and 3 types of messages:

1. Iterable streams, similar to WebSocket (it's name inspiration)
2. Remote procedure calls (RPC; this waits for a response)
3. Notify (like RPC but don't wait for the response)

It is entirely async (must be run in a coroutine) and implements flow control, so you don't have to worry about overwhelming the destination script's event queue. The number of in-flight messages to send without a reply is configurable by the `bufferSize` parameter of `ChatSocket.connect`. This allows you to send data as fast as lag will allow, without needing to be conservative and limiting yourself to one in-flight message at once (I did that a lot in LSL because this is so hard to get right without coroutines)

Caveat: all data sent over a ChatSocket must be serializable by [`lljson.slencode`](https://suzanna-linn.github.io/slua/moving-lljson).

In [examples](examples), is a pair of scripts that make use of all of ChatSocket's features to compare 2 prim's inventories, and send any missing items from sender to receiver:
1. Rez an empty collector prim and add [`inventory-audit-receiver.luau`](examples/inventory-audit-receiver.luau)
2. Rez all the prims who's inventories you want to compare. They need to be full perm.
3. Drop [`inventory-audit-sender.luau`](examples/inventory-audit-sender.luau) into each prim in turn.
4. The collector prim now contains all the de-duplicated items from the senders
5. Chat log tells you which prims had mismatched inventory.

Note: to actually run the scripts, you may want to grab the compiled version out of [examples-compiled](examples-compiled), as you currently need [sl-vscode-plugin](https://github.com/secondlife/sl-vscode-plugin) in order to use `require()` during Lua beta.

## API:
```luau
local ChatSocket = require("@tavatar/ChatSocket")
ChatSocket.connect(id: uuid, channel: number?, bufferSize: number?): Socket
```
Establish a 2-way connection.
- If `channel` is `nil`, a random channel will be chosen. Access it with `socket.channel`
- `bufferSize` specifies how many unacknowledged messages the socket allows to be in flight at once. Default is 20.
  - In other words, how many entries of the remote script's 64-entry event queue to claim for this socket.
  - This "buffer" is not directly managed by this script; it is the remote script's event queue.

ChatSocket does not help you discover what nearby prims may be willing to establish a ChatSocket withh you. Handshaking is left up to the scripter, as it's very application-specific.

Both prims need to set up the socket and all streams before sending any messages

### Socket
```luau
local socket = ChatSocket.connect(...)
socket:remoteFunction(endpoint: string, func: (...any) -> ...any, arg1: any?): ()
```
register the given function to receive rpc or notify messages
```luau
socket:call(endpoint: string, ...): ...
```
call a registered remoteFunction on the other prim, wait for the response, and return the result
```luau
socket:notify(endpoint: string, ...): ()
```
call a registered remoteFunction on the other prim. The remote prim will not send a response, and this call will not wait for it. notify can still block due to flow control
```luau
socket:openStream(channel: string): Stream<any>
```
Open a named data stream between the two prims
```luau
socket:close()
socket:waitUntilClosed()
```

### Streams

Streams are the main reason this library exists. They abstract away the pattern I find myself using all the time of:
1. create as much data as fits in a 1024 byte `ll.RegionSayTo` message
2. send the message
3. repeat until all data is sent

ChatSocket Streams take care of that. You just need a for loop on both sides.

Receiver side:
```luau
local stream = socket:openStream<string, uuid>("streamName")
for name, id in stream do
    -- do processing
    -- The loop will yield when no data is yet available,
    -- and exit when the remote side calls stream:close()
end
```

Sender side:
```luau
local stream = socket:openStream<string, uuid>("streamName")
for i = 1, 10 do
    stream:send("hello", NULL_KEY)
end
stream:close() -- don't forget this. It lets the remote for loop exit
```

Sender also has
```luau
stream:flush()
```
if you need to send unsent data now rather than when the stream has accumulated 1024 bytes (the maximum chat message size)

## TODO
- implement a timeout that closes the socket after a message has been unacknowledged for some time
- allow RPC endpoints to be async. Currently they throw an error if you try to `coroutine.yield()`