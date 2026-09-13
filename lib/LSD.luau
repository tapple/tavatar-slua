--!strict

local JSON_OPTIONS: LLJsonEncodeOptions = {tight = true}

local LSDMetaMeta = {}
local LSDMeta = setmetatable({}, LSDMetaMeta)
LSDMeta.__index = LSDMeta
type LSDStruct = {prefix: string, pass: string?}
export type LSD = setmetatable<LSDStruct, typeof(LSDMeta)>
local LSD = setmetatable({prefix=""}, LSDMeta) :: LSD

function LSDMeta.get(self: LSD, key: string): any?
    local rawvalue: string
    if self.pass then
        rawvalue = ll.LinksetDataReadProtected(self.prefix .. key, self.pass)
    else
        rawvalue = ll.LinksetDataRead(self.prefix .. key)
    end
    if rawvalue == "" then
        return nil
    else
        return lljson.slencode(rawvalue, JSON_OPTIONS)
    end
end

function LSDMeta.set(self: LSD, key: string, value: any?): number?
    local rawvalue = if value == nil then "" else 
    
    if self.pass then
        value = ll.LinksetDataReadProtected(self.prefix .. key, self.pass)
    else
        value = ll.LinksetDataRead(self.prefix .. key)
    end
    if value == "" then
        return nil
    else
        return lljson.sldecode(value)
    end
end

return LSD
