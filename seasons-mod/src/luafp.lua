----------------------------------------------------------------------------------------------------
-- LUA Functional Programming library
----------------------------------------------------------------------------------------------------
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

luafp = {}

function luafp.reduce(list, func, accum)
    for _, item in ipairs(list) do
        accum = func(accum, item)
    end

    return accum
end

function luafp.map(list, func)
    local res = {}

    for i, item in ipairs(list) do
        res[i] = func(item)
    end

    return res
end

