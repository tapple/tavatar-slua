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

--------------------------------

type AuditReceiver = {
    socket: Socket,
    auditStream: Stream<(string, uuid)>,
    requestStream: Stream<(string)>,
    toReceive: {[string]: uuid},
}

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