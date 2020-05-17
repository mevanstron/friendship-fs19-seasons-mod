----------------------------------------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------------------------------------
-- Purpose:  Wrapper for logging
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

Logging = {}

function Logging.warning(message, ...)
    print(string.format("  Seasons Warning: " .. message, ...))
end

function Logging.error(message, ...)
    print(string.format("  Seasons Error: " .. message, ...))
end

function Logging.info(message, ...)
    print(string.format("  Seasons Info: " .. message, ...))
end

function Logging.fatal(message, ...)
    error(string.format("  Seasons Error: " .. message, ...))
end

function Logging.table(t)
    setFileLogPrefixTimestamp(false)

    local print_r_cache = {}

    local function sub_print_r(t, indent)
        if (print_r_cache[tostring(t)]) then
            print(indent .. "*" .. tostring(t))
        else
            print_r_cache[tostring(t)] = true
            if (type(t) == "table") then
                for pos, val in pairs(t) do
                    pos = tostring(pos)

                    if (type(val) == "table") then
                        print(indent .. "[" .. pos .. "] => " .. tostring(t) .. " {")
                        sub_print_r(val, indent .. string.rep(" ", string.len(pos) + 8))
                        print(indent .. string.rep(" ", string.len(pos) + 6) .. "}")
                    elseif (type(val) == "string") then
                        print(indent .. "[" .. pos .. '] => "' .. val .. '"')
                    else
                        print(indent .. "[" .. pos .. "] => " .. tostring(val))
                    end
                end
            else
                print(indent .. tostring(t))
            end
        end
    end

    if (type(t) == "table") then
        print(tostring(t) .. " {")
        sub_print_r(t, "  ")
        print("}")
    else
        sub_print_r(t, "  ")
    end

    print()

    setFileLogPrefixTimestamp(true)
end
