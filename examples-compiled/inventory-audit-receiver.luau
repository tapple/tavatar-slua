-- ================ sl-vscode-plugin meta ================
-- @file lsl_scripts/debugging/inventory-audit-receiver.luau
-- @hash 4e9d20c49bd0ffe8e7b240399b14184da4ef7b5b8fb1159c8f1aab18dc25b3c8
-- @date 2026-09-07 16:28:28
-- =======================================================
(function()
    local modules = {
-- @module 1 workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau
(function()
-- @line 1 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--!strict

-- @line 3 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local module = {}
module.sockets = {} :: {Socket}

-- @line 6 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
---------------------------- Types ---------------------------
--------------------------------------------------------------

-- @line 10 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
type PDU = { -- Protocol Data Unit
    -- flow control
    y: number?, -- sYn: sending sequence number
    k: number?, -- acK: acknowledging sequence number
    close: true?, -- close the connection

-- @line 16 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
    -- payload type: id
    n: string?, -- asyNc/Notify: asynchronous function/notification name
    f: string?, -- synchronous function name
    r: number?, -- synchronous function response sequence number
    q: string?, -- stream/queue name

-- @line 22 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
    -- payload
    p: any, -- function parameters/return values or stream payload
}

-- @line 26 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local SocketClass = {}
SocketClass.__index = SocketClass
type SocketStruct = {
    -- ll.Listen/ll.RegionSayTo state
    handle: number,
    channel: number,
    remoteId: uuid,

-- @line 34 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
    -- flow control
    sequence: number, -- last sent sequence number
    acknowledged: number, -- last acknowledged sequence number
    received: number, -- last inbound sequence number (for statistics only)
    bufferSize: number, -- number of messages allowed to be sent without acknowledgement.
    sendQ: {thread}?, -- threads waiting to send. nil means closed

-- @line 41 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
    -- features
    functionHandlers: {[string]: RemoteFunction}, -- functions that can be called by the other side
    functionsAwaiting: {thread}, -- function calls awaiting response, by sequence number
    streamHandlers: {[string]: any}, -- Stream
    onCloseAwaiting: {thread}, -- threads waiting for the socket to close
}
export type Socket = setmetatable<SocketStruct, typeof(SocketClass)>

-- @line 49 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
----------------------------- Debug --------------------------
--------------------------------------------------------------

--[[
local function _debug(...)
    print(ll.GetScriptName(), ...)
end

-- print a pdu, but with the fields in a sane order and payload truncated
local function _printPDU(pdu: any): string
    if type(pdu) == "string" then
        pdu = lljson.sldecode(pdu)
    end
    local keys: {keyof<PDU>} = {"y", "k", "close", "n", "f", "r", "q"}
    local msg ="{"
    local v: any
    for _, k in keys do
        v = pdu[k]
        if v then msg ..= `"{k}":{lljson.encode(v)},` end
    end
    if not pdu.p then return msg:sub(1, -2) .. '}' end
    msg ..= '"p":'
    v = pdu.p[1]
    if v then
        msg ..= `[{lljson.slencode(v)},...]`
    else
        msg ..= `{lljson.slencode(pdu.p)}`
    end
    msg ..= "}"
    return msg
end
--]]

--[[ Show hovertext about the state of the library
local function _debugHovertext()
    local msg = ""
    local i = 0
    for channel, socket in module.sockets do
        i += 1
        msg ..= `--channel {socket.channel}--\n`
        msg ..= `sent {socket.sequence}\n`
        msg ..= `recv {socket.received}\n`
        msg ..= `unack {socket.sequence - socket.acknowledged}\n`
        msg ..= `queue {socket.sendQ and #socket.sendQ}\n`
    end
    if i == 0 then msg = "No sockets" end
    ll.SetText(msg, vector(1, 1, 0), 1)
end
LLTimers:every(0.1, _debugHovertext)
--]]

-- @line 101 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
---------------------------- Common --------------------------
--------------------------------------------------------------

-- @line 105 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local function warn(message: string, channel: number)
    print(`[ChatSocket {channel}]: {message}`)
end

-- @line 109 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local function thisThread(): thread
    return coroutine.running() or error("Must be called from a coroutine")
end


-- @line 114 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
---------------------------- Socket --------------------------
--------------------------------------------------------------

-- @line 118 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function SocketClass.waitUntilClosed(self: Socket)
    table.insert(self.onCloseAwaiting, thisThread())
    coroutine.yield()
end

-- @line 123 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local function socketSendRaw(socket: Socket, message: string)
    -- _debug(`socketSendRaw({socket.channel}, {message})`)
    assert(socket.sendQ, "Socket is closed")
    if socket.sequence - socket.acknowledged > socket.bufferSize then
        table.insert(socket.sendQ, thisThread())
        coroutine.yield()
    end
    ll.RegionSayTo(socket.remoteId, socket.channel, message)
end


-- @line 134 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
---------------- Functions/Remote Procedures -----------------
--------------------------------------------------------------

-- @line 138 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local JSON_CONFIG: LLJsonEncodeOptions = {tight = true}

-- @line 140 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
type RemoteFunction = {
    func: (...any) -> (...any),
    arg1: any,
}

-- @line 145 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function SocketClass.remoteFunction(self: Socket, endpoint: string, func: (...any) -> ...any, arg1: any?)
    self.functionHandlers[endpoint] = {
        func = func,
        arg1 = arg1,
    }
end

-- @line 152 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function SocketClass.notify(self: Socket, endpoint: string, ...)
    self.sequence += 1
    local pduStr = lljson.slencode({y=self.sequence, n=endpoint, p={...}})
    socketSendRaw(self, pduStr)
end

-- @line 158 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function SocketClass.call(self: Socket, endpoint: string, ...)
    self.sequence += 1
    local pduStr = lljson.slencode({y=self.sequence, f=endpoint, p={...}})
    socketSendRaw(self, pduStr)
    self.functionsAwaiting[self.sequence] = thisThread()
    local response = coroutine.yield()
    return unpack(response, 1, table.maxn(response))
end


-- @line 168 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
--------------------------- Streams --------------------------
--------------------------------------------------------------

-- @line 172 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local PLACEHOLDER = "\u{378}\u{5cd}" -- unused greek char, unused armenian char
local PLACEHOLDER_JSON = '"' .. PLACEHOLDER .. '"'

-- @line 175 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local StreamClass = {}
StreamClass.__index = StreamClass
type StreamStruct<T...> = {
    socket: Socket,
    outboundPDU: PDU,
    outbound: {string}?, -- nil means closed
    outboundBytes: number,
    outboundHead: string,
    outboundTail: string,
    inbound: {any}?,  -- packed T... . nil means closed
    recvQ: {thread},
}
export type Stream<T...> = setmetatable<StreamStruct<T...>, typeof(StreamClass)>

-- @line 189 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function SocketClass.openStream(self: Socket, channel: string): Stream<any>
    local pdu = {y=self.sequence, q=channel, p={PLACEHOLDER}}
    local left, right = unpack(string.split(
        lljson.slencode(pdu, JSON_CONFIG), PLACEHOLDER_JSON))
    local struct: StreamStruct<any> = {
        socket = self,
        outboundPDU = {y=self.sequence, q=channel, p={PLACEHOLDER}},
        outboundHead = left,
        outboundTail = right,
        outboundBytes = #left + #right,
        outbound = {},
        inbound = {},
        recvQ = {},
    }
    local stream: Stream<any> = setmetatable(struct, StreamClass)
    self.streamHandlers[channel] = stream
    return stream
end

-- @line 208 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local function _streamPack(self: Stream<any>, pdu: PDU): (string, string, string)
    -- Pack all pending stream data into the given pdu, reset the stream, and return the encoded pdu
    -- _debug("_streamFlush()")
    assert(self.outbound, "Stream is closed")
    local head, tail = unpack(string.split(lljson.slencode(pdu, JSON_CONFIG), PLACEHOLDER_JSON))
    local pduStr = head .. table.concat(self.outbound, ",") .. tail
    self.outboundBytes = #self.outboundHead + #self.outboundTail
    table.clear(self.outbound)
    return pduStr, head, tail
end

-- @line 219 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function StreamClass.flush(self: Stream<any>)
    -- _debug("StreamClass.flush()")
    local pduStr
    self.socket.sequence += 1
    self.outboundPDU.y = self.socket.sequence
    pduStr, self.outboundHead, self.outboundTail = _streamPack(self, self.outboundPDU)
    socketSendRaw(self.socket, pduStr)
end

-- @line 228 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
-- send a single item, without wrapping varargs
function StreamClass._send(self: Stream<any>, item: any)
    -- _debug("StreamClass._send()")
    assert(self.outbound, "Stream is closed")
    local nextLine = lljson.slencode(item, JSON_CONFIG)
    local newPduSize = self.outboundBytes + 1 + #nextLine
    if newPduSize < 1024 then
        self.outboundBytes = newPduSize
    else
        self:flush()
        self.outboundBytes += #nextLine 
    end
    table.insert(self.outbound, nextLine)
end

-- @line 242 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
-- send varargs as a single message
function StreamClass.send<T...>(self: Stream<T...>, ...: T...)
    assert(select(1, ...) ~= nil, "Stream.send first argument must not be nil")
    self:_send({...})
end

-- @line 248 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function StreamClass.__iter<T...>(self: Stream<T...>)
    local item_iterator = function(self: Stream<T...>): (T...)
        while true do
            if self.inbound == nil then
                -- _debug("__iter: stream is closed")
                return -- stream is closed
            elseif #self.inbound > 0 then
                local item: any = table.remove(self.inbound, 1)
                if item == lljson.null then
                    self.inbound = nil -- close the stream
                    -- _debug("__iter: closing stream")
                    for _, thread in self.recvQ do
                        coroutine.resume(thread)
                    end
                    return 
                end
                -- _debug(`__iter: returning {lljson.slencode(item)}`)
                return table.unpack(item, 1, table.maxn(item))
            elseif #self.inbound == 0 then
                -- _debug(`__iter: pausing {thread}`)
                table.insert(self.recvQ, thisThread())
                coroutine.yield()
                -- _debug(`__iter: resuming {thread}`)
            end
        end
    end
    return item_iterator, self, true
end

-- @line 276 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function StreamClass.close<T>(self: Stream<T>)
    if self.outbound then
        self:_send(lljson.null)
        self:flush()
        self.outbound = nil
    end
end


-- @line 285 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
---------------------------- Module --------------------------
--------------------------------------------------------------

-- @line 289 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
-- Establish an outbound 2-way connection.
-- If channel is nil, a random channel will be chosen.
-- `bufferSize` specifies how many unacknowledged messages the socket allows to be in flight at once. Default is 20.
-- In other words, how many entries of the remote script's 64-entry event queue to claim for this socket.
-- This "buffer" is not directly managed by this script; it is the remote script's event queue.
function module.connect(id: uuid, channel: number?, bufferSize: number?): Socket
    if next(module.sockets :: {any}) == nil then
        LLEvents:on("listen", listenEventHandler)
    end
    if module.sockets[channel] then
        error(`Attempt to connect on channel {channel} which is already in use`)
    elseif not channel then
        repeat
            channel = math.random(-2^31, -2^10)
        until not module.sockets[channel]
    end
    -- I doubt random sequence numbers are neccesary, and having them start at 0
    -- means it can double as a sent/received message count without extra memory.
    --local sequence = math.random(0, 2^29)
    local socket: Socket = setmetatable({
        handle = ll.Listen(channel, "", id, ""),
        channel = channel,
        remoteId = id,
        sequence = 0, --sequence,
        acknowledged = 0, --sequence,
        received = 0,
        bufferSize = bufferSize or 20,
        sendQ = {},
        onCloseAwaiting = {},
        functionHandlers = {},
        functionsAwaiting = {},
        streamHandlers = {},
    }, SocketClass)
    module.sockets[channel] = socket
    return socket
end

-- @line 326 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local function _socketCloseSender(self: Socket, ack: number?)
    -- _debug(`_socketCloseSender({self.channel}, {ack})`)
    if not self.sendQ then return end -- already closed
    for channel, stream in self.streamHandlers do
        stream:close()
    end
    self.sequence += 1
    local pduStr = lljson.slencode({y=self.sequence, k=ack, close=true})
    socketSendRaw(self, pduStr)
    assert(#self.sendQ == 0, "Socket closed with unfinished threads")
    self.sendQ = nil
end

-- @line 339 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
local function _socketCloseReceiver(self: Socket)
    -- _debug(`_socketCloseReceiver({self.channel})`)
    ll.ListenRemove(self.handle)
    module.sockets[self.channel] = nil
    if next(module.sockets :: {any}) == nil then
        LLEvents:off("listen", listenEventHandler)
    end
    for _, thread in self.onCloseAwaiting do
        coroutine.resume(thread)
    end
end

-- @line 351 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function SocketClass.close(self: Socket)
    _socketCloseSender(self)
end


-- @line 356 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
--------------------------------------------------------------
------------------------ Listen Event ------------------------
--------------------------------------------------------------

-- @line 360 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
function listenEventHandler(channel: number, name: string, id: uuid, message: string)
    -- _debug(`listenEventHandler({channel}, {name}, {id},\n{message})`)
    local socket = module.sockets[channel]
    if not socket or socket.remoteId ~= id then return end

-- @line 365 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
    local valid: boolean, pdu: PDU = pcall(lljson.sldecode, message)
    if not valid then
        warn(`Failed to decode PDU ({pdu}): {message})`, channel)
        return
    end
    -- _debug(`listen({channel},,,{_printPDU(pdu)})`)
    if not pdu.y and not pdu.k then
        warn(`PDU missing sequence numbers: {message}`, channel)
        return
    end
    if pdu.q then -- stream/queue message
        local stream = socket.streamHandlers[pdu.q]
        if not stream then
            warn(`PDU with unregistered stream: {message}`, channel)
        elseif not pdu.p then
            warn(`Stream PDU without payload: {message}`, channel)
        else
            table.extend(stream.inbound, pdu.p)
            while stream.inbound and #stream.inbound > 0 and #stream.recvQ > 0 do
                coroutine.resume(table.remove(stream.recvQ, 1) :: thread)
            end
        end
    end
    if pdu.r then -- remote function response
        -- table.remove doesn't work here because it's a dict table
        local thread = socket.functionsAwaiting[pdu.r]
        if not thread then
            warn(`PDU with unrequested function reply: {message}`, channel)
            -- for k, v in socket.functionsAwaiting do _debug("awaiting", k, v) end
        else
            socket.functionsAwaiting[pdu.r] = nil
            coroutine.resume(thread, pdu.p)
        end
    end
    if pdu.y then -- inbound message
        socket.received = pdu.y
        local responsePDU: PDU = {k = pdu.y, close=pdu.close}
        local responsePDUStr: string? = nil
        if pdu.f or pdu.n then
            local functionHandler = socket.functionHandlers[pdu.f or pdu.n]
            if pdu.f and not pdu.y then
                warn(`function PDU missing sequence number: {message}`, channel)
            elseif not functionHandler then
                warn(`function PDU with unregistered function: {message}`, channel)
            else
                -- TODO: allow async functions to be remotely called
                local response
                if functionHandler.arg1 == nil then
                    response = {functionHandler.func(unpack(pdu.p, 1, table.maxn(pdu.p)))}
                else
                    response = {functionHandler.func(functionHandler.arg1, unpack(pdu.p, 1, table.maxn(pdu.p)))}
                end
                if pdu.f then
                    responsePDU = {
                        k = pdu.y,
                        r = pdu.y,
                        p = response,
                    }
                end
            end
        end
        if pdu.close and socket.sendQ then --
            _socketCloseSender(socket, pdu.y)
        else
            if not responsePDU.p then
                -- If the ack would otherwise be empty, try to stuff it with some pending stream data. This
                -- can save around 50% of messages if both sides are sending stream data at similar rates
                for channel, stream in socket.streamHandlers do
                    if stream.outbound and #stream.outbound > 0 then
                        responsePDU.q = channel
                        responsePDU.p = {PLACEHOLDER}
                        responsePDUStr = _streamPack(stream, responsePDU)
                        break
                    end
                end
            end
            -- _debug(`socketSendAck({socket.channel}, {_printPDU(responsePDUStr or responsePDU)})`)
            if responsePDUStr == nil then responsePDUStr = lljson.slencode(responsePDU) end
            -- send directly. ACKs are not subject to flow control (they are the flow control)
            ll.RegionSayTo(socket.remoteId, socket.channel, responsePDUStr :: string)
        end
    end
    if pdu.k then -- acknowledgement message
        local diff = pdu.k - socket.acknowledged - 1
        if diff < 0 then
            warn(`Out-of-order message detected`, channel)
        elseif diff > 0 then
            warn(`{diff} dropped messages detected`, channel)
        end
        if diff >= 0 then
            socket.acknowledged = pdu.k
        end
        while socket.sendQ and #socket.sendQ > 0 and socket.sequence - socket.acknowledged <= socket.bufferSize do
            coroutine.resume(table.remove(socket.sendQ, 1) :: thread)
        end
        if pdu.close then
            _socketCloseReceiver(socket)
        end
    end
end


-- @line 467 "workspace:///teeglepet/lsl_scripts/vehicle/modules/ChatSocket.luau"
return table.freeze(module)
end),
    }
    local cache = {}
    function require(mod)
        if not cache[mod] then
            if not modules[mod] then
                error(`unknown module '{mod}'`)
            end
            cache[mod] = dangerouslyexecuterequiredmodule(modules[mod])
        end
        return cache[mod]
    end
end)()
--@line 1 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
--!strict
local ChatSocket = require(1)
type Socket = ChatSocket.Socket
type Stream<T...> = ChatSocket.Stream<T...>

-- @line 6 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
--------- Utils -------------

-- @line 8 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
local function errorHandler(msg)
    ll.Say(DEBUG_CHANNEL, debug.traceback(msg, 2))
end

-- @line 12 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
local function coroLoudWrap(f)
    -- works the same as coroutine.wrap, but if the coroutine has an
    -- unhandled error, print a stack trace, just like how the main thread does
    return function(...)
        return coroutine.resume(coroutine.create(xpcall), f, errorHandler, ...)
    end
end

-- @line 20 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
--------------------------------

-- @line 22 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
type AuditReceiver = {
    socket: Socket,
    auditStream: Stream<(string, uuid)>,
    requestStream: Stream<(string)>,
    toReceive: {[string]: uuid},
}

-- @line 29 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
local function checkInventory(self: AuditReceiver, done: boolean?): boolean
    for itemName, remoteItemId in table.clone(self.toReceive) do
        local localItemId = ll.GetInventoryKey(itemName)
        local localItemType = ll.GetInventoryType(itemName)
        if localItemType == INVENTORY_NONE then
            if done then
                print("ERROR; never received: " .. itemName)
            end 
        elseif localItemId == remoteItemId then
            self.toReceive[itemName] = nil
        else
            print("ERROR; received mismatched item: " .. itemName)
        end
    end
    -- print("checkInventory", lljson.slencode(self.toReceive))
    return next(self.toReceive) == nil
end

-- @line 46 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
local function runRequester(self: AuditReceiver)
    for itemName: string, remoteItemId in self.auditStream do
        -- print("auditStream received:", itemName, remoteItemId)
        local localItemId = ll.GetInventoryKey(itemName)
        local localItemType = ll.GetInventoryType(itemName)
        if localItemType == INVENTORY_NONE then
            self.requestStream:send(itemName)
            self.toReceive[itemName] = remoteItemId
        elseif remoteItemId == localItemId then
            -- ok
        elseif localItemId == NULL_KEY then
            print("ERROR; not full perm: " .. itemName)
        else
            print("AUDIT MISMATCH: " .. itemName)
        end
    end
    -- print("auditStream finished")
    self.requestStream:close()
end

-- @line 66 "workspace:///teeglepet/lsl_scripts/debugging/inventory-audit-receiver.luau"
local CHANNEL = 44011
local MSG_HELLO = "hello audit"
ll.Listen(CHANNEL, "", NULL_KEY, MSG_HELLO);
function LLEvents.listen(channel: number, name: string, id: uuid, msg: string)
    if channel == CHANNEL and msg == MSG_HELLO then
        local socket = ChatSocket.connect(id)
        local auditReceiver: AuditReceiver = {
            socket = socket,
            auditStream = socket:openStream("audit"),
            requestStream = socket:openStream("request"),
            toReceive = {},
        }
        socket:remoteFunction("checkInventory", checkInventory, auditReceiver)
        -- socket:remoteFunction("llGetInventoryName", ll.GetInventoryName) -- test
        coroLoudWrap(runRequester)(auditReceiver)
        ll.RegionSayTo(id, channel, lljson.slencode({"audit ready", socket.channel}))
    end
end