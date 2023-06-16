local fmt = string.format
__print = print

function __assert_type(value, typeOfValue)
    if type(value) ~= typeOfValue then -- Wrong parameter type, string required. Provided param 'nil' is type of nil
        error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",
                typeOfValue, tostring(value), type(value)),
            3)
    end
end

net = {}
function net.HTTPCall()
    return {
        request = function(_, url, opts)
            local options = (opts or {}).options or {}
            local data = options.data and json.encode(options.data) or nil
            local status,res,headers = __HTTP(options.method or "GET", url, options, data )
            if status < 303 and opts.success and type(opts.success)=='function' then
                setTimeout(function() opts.success({status=status, data=res,headers=headers}) end,0)
            elseif opts.error and type(opts.error)=='function' then
                setTimeout(function() opts.error(status,headers) end,0)
            end
        end
    }
end

local function callHC3(method, path, data)
    local url = fmt("http://%s/api%s", __config.host, path)
    local options = { 
        headers = {
            ['Authorization'] = __config.creds,
            ["Accept"] = '*/*', ["X-Fibaro-Version"] = "2", ["Fibaro-User-PIN"] = __config.pin,
            ["Content-Type"] = "application/json",
        }
    }
    local status, res, headers = __HTTP(method, url, options, data and json.encode(data) or nil)
    if status >= 303 then
        return nil,status
        --error(fmt("HTTP error %d: %s", status, res))
    end
    return res and type(res)=='string' and json.decode(res) or nil,status
end

api = {
    get = function(url) return callHC3("GET", url) end,
    post = function(url, data) return callHC3("POST", url, data) end,
    put = function(url, data) return callHC3("PUT", url, data) end,
    delete = function(url, data) return callHC3("DELETE", url, data) end
}


function setInterval(fun, ms)
    local ref = {}
    local function loop()
        fun()
        ref[1] = setTimeout(loop, ms)
    end
    ref[1] = setTimeout(loop, ms)
    return ref
end

function clearInterval(ref)
    clearTimeout(ref[1])
end

fibaro = {}
hub = fibaro

function __assert_type(value, typeOfValue)
    if type(value) ~= typeOfValue then -- Wrong parameter type, string required. Provided param 'nil' is type of nil
        error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s", typeOfValue, tostring(value),
            type(value)), 3)
    end
end

function string.split(str, sep)
    local fields, s = {}, sep or "%s"
    str:gsub("([^" .. s .. "]+)", function(c)
        fields[#fields + 1] = c
    end)
    return fields
end

function fibaro.alarm(arg1, action)
    if type(arg1) == "string" then
        fibaro.__houseAlarm(arg1)
    else
        __assert_type(arg1, "number")
        __assert_type(action, "string")
        local url = "/alarms/v1/partitions/" .. arg1 .. "/actions/arm"
        if action == "arm" then
            api.post(url)
        elseif action == "disarm" then
            api.delete(url)
        else
            error("Wrong parameter: " .. action .. ". Available parameters: arm, disarm", 2)
        end
    end
end

function fibaro.__houseAlarm(action)
    __assert_type(action, "string")
    local url = "/alarms/v1/partitions/actions/arm"
    if action == "arm" then
        api.post(url)
    elseif action == "disarm" then
        api.delete(url)
    else
        error("Wrong parameter: '" .. action .. "'. Available parameters: arm, disarm", 3)
    end
end

function fibaro.alert(alertType, ids, notification, isCritical, subject)
    __assert_type(alertType, "string")
    __assert_type(ids, "table")
    __assert_type(notification, "string")
    local isDefined = "false"
    local actions = {
        email = "sendGlobalEmailNotifications",
        push = "sendGlobalPushNotifications",
        simplePush = "sendPush",
        sms = "sendGlobalSMSNotifications"
    }
    if actions[alertType] == nil then
        error("Wrong parameter: '" .. alertType .. "'. Available parameters: email, push, simplePush", 2)
    end
    for _, id in ipairs(ids) do
        __assert_type(id, "number")
    end
    for _, id in ipairs(ids) do
        fibaro.call(id, actions[alertType], notification, isDefined)
    end
end

function fibaro.emitCustomEvent(name)
    __assert_type(name, "string")
    api.post("/customEvents/" .. name)
end

function fibaro.call(deviceId, actionName, ...)
    __assert_type(actionName, "string")
    if type(deviceId) == "table" then
        for _, id in pairs(deviceId) do
            __assert_type(id, "number")
        end
        for _, id in pairs(deviceId) do
            fibaro.call(id, actionName, ...)
        end
        return
    end
    __assert_type(deviceId, "number")
    local arg = { ... }; -- arg = #arg > 0 and arg or nil
    api.post("/devices/" .. deviceId .. "/action/" .. actionName, {
        args = arg
    })
end

function fibaro.callGroupAction(actionName, actionData)
    __assert_type(actionName, "string")
    __assert_type(actionData, "table")
    local response, status = api.post("/devices/groupAction/" .. actionName, actionData)
    if status ~= 202 then
        return nil
    else
        return response["devices"]
    end
end

function fibaro.get(deviceId, propertyName)
    __assert_type(deviceId, "number")
    __assert_type(propertyName, "string")
    local property = __fibaro_get_device_property(deviceId, propertyName)
    if property then
        return property.value, property.modified
    end
end

function fibaro.getValue(deviceId, propertyName)
    __assert_type(deviceId, "number")
    __assert_type(propertyName, "string")
    local property = __fibaro_get_device_property(deviceId, propertyName)
    if property then
        return property.value
    end
end

function fibaro.getType(deviceId)
    __assert_type(deviceId, "number")
    return (__fibaro_get_device(deviceId) or {}).type
end

function fibaro.getName(deviceId)
    __assert_type(deviceId, 'number')
    return (__fibaro_get_device(deviceId) or {}).name
end

function fibaro.getRoomID(deviceId)
    __assert_type(deviceId, 'number')
    return (__fibaro_get_device(deviceId) or {}).roomID
end

function fibaro.getSectionID(deviceId)
    __assert_type(deviceId, 'number')
    local dev = __fibaro_get_device(deviceId)
    if dev ~= nil then
        return __fibaro_get_room(dev.roomID).sectionID
    end
end

function fibaro.getRoomName(roomId)
    __assert_type(roomId, 'number')
    return (__fibaro_get_room(roomId) or {}).name
end

function fibaro.getRoomNameByDeviceID(deviceId)
    __assert_type(deviceId, 'number')
    local dev = __fibaro_get_device(deviceId)
    return dev and fibaro.getRoomName(dev.roomID) or nil
end

function fibaro.getDevicesID(filter)
    if type(filter) ~= 'table' or (type(filter) == 'table' and next(filter) == nil) then
        return fibaro.getIds(__fibaro_get_devices())
    end
    local buff = {}
    local function out(s)
        buff[#buff + 1] = s
    end
    out('/?')
    for c, d in pairs(filter) do
        if c == 'properties' and d ~= nil and type(d) == 'table' then
            for a, b in pairs(d) do
                if b == "nil" then
                    out('property=' .. tostring(a))
                else
                    out('property=[' .. tostring(a) .. ',' .. tostring(b) .. ']')
                end
            end
        elseif c == 'interfaces' and d ~= nil and type(d) == 'table' then
            for _, b in pairs(d) do
                out('interface=' .. tostring(b))
            end
        else
            out(tostring(c) .. "=" .. tostring(d))
        end
    end
    local args = table.concat(buff, '&')
    return fibaro.getIds(api.get('/devices' .. args))
end

function fibaro.getIds(devices)
    local ids = {}
    for _, a in pairs(devices) do
        if a ~= nil and type(a) == 'table' and a['id'] ~= nil and a['id'] > 3 then
            table.insert(ids, a['id'])
        end
    end
    return ids
end

function fibaro.getGlobalVariable(name)
    __assert_type(name, 'string')
    local g = __fibaro_get_global_variable(name)
    if g then
        return g.value, g.modified
    end
end

function fibaro.setGlobalVariable(name, value)
    __assert_type(name, 'string')
    __assert_type(value, 'string')
    api.put("/globalVariables/" .. name, {
        ["value"] = tostring(value),
        ["invokeScenes"] = true
    })
end

function fibaro.scene(action, ids)
    __assert_type(action, "string")
    __assert_type(ids, "table")
    local availableActions = {
        execute = true,
        kill = true
    }
    assert(availableActions[action], "Wrong parameter: " .. action .. ". Available actions: execute, kill")
    for _, id in ipairs(ids) do
        __assert_type(id, "number")
    end
    for _, id in ipairs(ids) do
        api.post("/scenes/" .. id .. "/" .. action)
    end
end

function fibaro.profile(action, profileId)
    __assert_type(profileId, "number")
    __assert_type(action, "string")
    local availableActions = {
        activateProfile = "activeProfile"
    }
    assert(availableActions[action], "Wrong parameter: " .. action .. ". Available actions: activateProfile")
    api.post("/profiles/" .. availableActions[action] .. "/" .. profileId)
end

function fibaro.getPartition(id)
    __assert_type(id, "number")
    return __fibaro_get_partition(id)
end

function fibaro.setTimeout(timeout, action)
    __assert_type(timeout, "number")
    __assert_type(action, "function")
    return setTimeout(action, timeout)
end

function fibaro.clearTimeout(timeoutId)
    __assert_type(timeoutId, "table")
    clearTimeout(timeoutId)
end

function fibaro.wakeUpDeadDevice(deviceID)
    __assert_type(deviceID, 'number')
    fibaro.call(1, 'wakeUpDeadDevice', deviceID)
end

function fibaro.sleep(ms)
    __assert_type(ms, "number")
    __fibaroSleep(ms)
end

local function d2str(...)
    local r, s = { ... }, {}
    for i = 1, #r do
        if r[i] ~= nil then
            s[#s + 1] = tostring(r[i])
        end
    end
    return table.concat(s, " ")
end
function fibaro.debug(tag, ...)
    __assert_type(tag, "string")
    __fibaro_add_debug_message(tag, d2str(...), "DEBUG")
end

function fibaro.warning(tag, ...)
    __assert_type(tag, "string")
    __fibaro_add_debug_message(tag, d2str(...), "WARNING")
end

function fibaro.trace(tag, ...)
    __assert_type(tag, "string")
    __fibaro_add_debug_message(tag, d2str(...), "TRACE")
end

function fibaro.error(tag, ...)
    __assert_type(tag, "string")
    __fibaro_add_debug_message(tag, d2str(...), "ERROR")
end

function fibaro.useAsyncHandler(value)
    __assert_type(value, "boolean")
    __fibaroUseAsyncHandler(value)
end

function fibaro.getHomeArmState()
    local ps, c = api.get("/alarms/v1/partitions") or {}, 0
    for _, p in ipairs(ps) do
        c = c + (p.armed and 1 or 0)
    end
    return c == #ps and "armed" or c == 0 and "disarmed" or "partially_armed"
end

function fibaro.isHomeBreached()
    for _, p in ipairs(api.get("/alarms/v1/partitions") or {}) do
        if p.breached then
            return true
        end
    end
    return false
end

function fibaro.isPartitionBreached(id)
    __assert_type(id, "number")
    local p = api.get("/alarms/v1/partitions/" .. id)
    return p and p.breached
end

function fibaro.getPartitionArmState(id)
    __assert_type(id, "number")
    local p = api.get("/alarms/v1/partitions/" .. id)
    if not p then
        error("Bad partitions id: " .. tostring(id))
    end
    return p.armed and "armed" or "disarmed"
end

function fibaro.getPartitions()
    return api.get("/alarms/v1/partitions") or {}
end

function fibaro.callUI(id, action, element, value)
    __assert_type(id, "number")
    __assert_type(action, "string")
    __assert_type(element, "string")
    value = value == nil and "null" or value
    local _, code = api.get(fmt("/plugins/callUIEvent?deviceID=%s&eventType=%s&elementName=%s&value=%s", id, action,
        element, value))
    if code == 404 then
        error(fmt("Device %s does not exists.", id), 3)
    end
end
