local _debug = {}

local NO_DEBUG = false
function _debug.print(...: any)
    if NO_DEBUG then return end
    local msg = ll.GetScriptName() .. ":" 
    local args = table.pack(...)
    for i = 1, args.n do
        msg ..= "   " .. (_debug.str(args[i]) or _debug.repr(args[i]))
    end
    while true do
        local rest = string.sub(msg, 1025)
        if rest ~= "" then
            msg = string.sub(msg, 1, 1024)
            local i = string.find(msg, "\n[^\n]*$")
            if i then
                rest = string.sub(msg, i + 1) .. rest
                msg = string.sub(msg, 1, i-1)
            end
        end
        print(msg)
        msg = rest
        if msg == "" then return end
        msg = "...\n" .. msg
    end
end

function _debug.f(msg: string, ...)
    -- if true then return end
    _debug.print(msg:format(...))
end

local STR = {
    ["nil"] = tostring,
    boolean = tostring,
    number = tostring,
    string = tostring,
    vector = tostring,
    quaternion = tostring,
    uuid = tostring,
}

function _debug.str(v: any): string?
    local t = typeof(v)
    return if STR[t] then STR[t](v) else nil
end

local REPR = {
    ["nil"] = tostring,
    boolean = tostring,
    number = tostring,
    string = function(s: string): string
        s = s:gsub("\\", "\\\\"):gsub("\n", "\\n")
        if not s:find('"') then
            return '"' .. s .. '"'
        elseif not s:find("'") then
            return "'" .. s .. "'"
        else
            return '"' .. s:gsub('"', '\\"') .. '"'
        end
    end,
    vector = function(v: vector): string
        return "vector(" .. v.x .. ", " .. v.y .. ", " .. v.z .. ")"
    end,
    quaternion = function(q: quaternion): string
        return "quaternion(" .. q.x .. ", " .. q.y .. ", " .. q.z .. ", " .. q.s .. ")"
    end,
    uuid = function(u: uuid): string
        return 'uuid("' .. tostring(u) .. '")'
    end,
}

-- https://snippets.bentasker.co.uk/posts/lua/recursively-print-table-printr-equivalent.html
function _debug.repr(data: any): string
    -- cache of tables already printed, to avoid infinite recursive loops
    local tablecache: {} = {}
    local buffer: string = ""
    local padder: string = "    "

    local function _dumpvar(d: any, depth: number)
        local t = typeof(d)
        local str = tostring(d)
        if REPR[t] then
            buffer ..= REPR[t](d)
        elseif (t == "table") then
            if next(d) == nil then
                buffer ..= "{}"
            elseif (tablecache[str]) then
                -- table already dumped before, so we dont
                -- dump it again, just mention it
                buffer ..= "<"..str..">\n"
            else
                tablecache[str] = true
                -- buffer ..= "{ -- "..str.."\n"
                buffer ..= "{\n"
                local i = 0
                for k: any, v: any in pairs(d) do
                    i += 1
                    buffer ..= padder:rep(depth+1)
                    local tk = type(k)
                    if i == k then  -- array part; no index
                    elseif tk == "string" and k:find("^[_%a][_%w]*$") then
                        buffer ..= k .. " = "
                    elseif REPR[tk] then
                        buffer ..= "["..REPR[tk](k).."] = "
                    else
                        buffer ..= "["..tostring(k).."] = "
                    end
                    _dumpvar(v, depth+1)
                    buffer ..= ",\n"
                end
                buffer ..= padder:rep(depth).."}"
            end
        else
            buffer ..= "("..t..") \""..str.."\"\n"
        end
    end
    _dumpvar(data, 0)
    return buffer
end

function _debug.hex(anInteger: number): string
    return ("0x%08x"):format(anInteger)
end

return table.freeze(setmetatable(_debug, {
    __call = function(_, ...) return _debug.print(...) end
}))