--!strict
local ChatSocket = require("../vehicle/modules/ChatSocket")
type Socket = ChatSocket.Socket
type Stream<T...> = ChatSocket.Stream<T...>

--------- Utils -------------

local function errorHandler(msg)
    ll.Say(DEBUG_CHANNEL, debug.traceback(msg, 2))
end

local function coroLoudWrap(f)
    -- works the same as coroutine.wrap, but if the coroutine has an
    -- unhandled error, print a stack trace, just like how the main thread does
    return function(...)
        return coroutine.resume(coroutine.create(xpcall), f, errorHandler, ...)
    end
end

--[[
local function aSleep(time: number)
    -- async sleep. Does not pause event loop if called from a coroutine
    local thread = coroutine.running()
    if thread then
        LLTimers:once(time, function() coroutine.resume(thread) end)
        coroutine.yield()
    else
        ll.Sleep(time)
    end
end
--]]

--------------------------------

type AuditSender = {
    socket: Socket,
    auditStream: Stream<(string, uuid)>,
    requestStream: Stream<(string)>,
}

local function runAuditSender(self: AuditSender)
    for i = 1, ll.GetInventoryNumber(INVENTORY_ALL) do
        local item = ll.GetInventoryName(INVENTORY_ALL, i)
        if item == ll.GetScriptName() then continue end
        self.auditStream:send(item, ll.GetInventoryKey(item))
        -- aSleep(0.01)
    end
    self.auditStream:close()
end

local function runInventorySender(self: AuditSender)
    local i = 0
    for itemName in self.requestStream do
        -- print("requestStream received:", itemName)
        ll.GiveInventory(self.socket.remoteId, itemName)
        i += 1
        if i % 100 == 0 then
            self.socket:notify("checkInventory")
        end
    end
    -- print("requestStream finished")
    local success: boolean = self.socket:call("checkInventory", true)
    if success then
        print("Audit succeeded")
    else
        print("Audit failed")
    end
    self.socket:close()
end

-- Async. Returns the nearby audit receiver's id and channel
local function findAuditReceiver(): (uuid, number)
    local CHANNEL = 44011
    local MSG_HELLO = "hello audit"
    local thread = coroutine.running()
    local listenHandle = ll.Listen(CHANNEL, "", NULL_KEY, "");
    local eventHandle = LLEvents:on("listen", function(channel: number, name: string, id: uuid, msg: string)
        if channel ~= CHANNEL then return end
        local valid, json = pcall(lljson.sldecode, msg)
        if not valid then return end
        local command, socketChannel = unpack(json)
        if command ~= "audit ready" then return end

        coroutine.resume(thread, id, socketChannel)
    end)
    ll.Say(CHANNEL, MSG_HELLO)
    local id, socketChannel = coroutine.yield()

    ll.ListenRemove(listenHandle)
    LLEvents:off("listen", eventHandle)
    return id, socketChannel
end

local function main()
    local id, socketChannel = findAuditReceiver()
    local socket = ChatSocket.connect(id, socketChannel)
    local auditSender: AuditSender = {
        socket = socket,
        auditStream = socket:openStream("audit"),
        requestStream = socket:openStream("request"),
    }
    -- print(socket:call("llGetInventoryName", INVENTORY_ALL, 1))
    coroLoudWrap(runAuditSender)(auditSender)
    coroLoudWrap(runInventorySender)(auditSender)
    socket:waitUntilClosed()
    -- print("die")
    ll.RemoveInventory(ll.GetScriptName())
end

coroLoudWrap(main)()