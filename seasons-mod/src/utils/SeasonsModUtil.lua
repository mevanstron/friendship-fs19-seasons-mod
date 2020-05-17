----------------------------------------------------------------------------------------------------
-- SeasonsUI
----------------------------------------------------------------------------------------------------
-- Purpose:  Constructor of the UI system for Seasons: installs HUDs and menus.
--           Also handles UI overrides.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsModUtil = {}

if GS_IS_CONSOLE_VERSION then
    -- On the console version, we need to reset all vanilla values we change

    local originalFunctions = {}
    local originalConstants = {}
    local tireTypes = {}

    -- Store the original function, if not done yet (otherwise it was already changed)
    local function storeOriginalFunction(target, name)
        if originalFunctions[target] == nil then
            originalFunctions[target] = {}
        end

        -- Store the original function
        if originalFunctions[target][name] == nil then
            originalFunctions[target][name] = target[name]
        end
    end

    function SeasonsModUtil.overwrittenFunction(target, name, newFunc)
        storeOriginalFunction(target, name)

        target[name] = Utils.overwrittenFunction(target[name], newFunc)
    end

    function SeasonsModUtil.overwrittenStaticFunction(target, name, newFunc)
        storeOriginalFunction(target, name)

        local oldFunc = target[name]
        target[name] = function (...)
            return newFunc(oldFunc, ...)
        end
    end

    function SeasonsModUtil.appendedFunction(target, name, newFunc)
        storeOriginalFunction(target, name)

        target[name] = Utils.appendedFunction(target[name], newFunc)
    end

    function SeasonsModUtil.prependedFunction(target, name, newFunc)
        storeOriginalFunction(target, name)

        target[name] = Utils.prependedFunction(target[name], newFunc)
    end

    function SeasonsModUtil.unregisterAdjustedFunctions()
        for target, functions in pairs(originalFunctions) do
            for name, func in pairs(functions) do
                target[name] = func
            end
        end
    end

    function SeasonsModUtil.overwrittenConstant(target, name, newVal)
        if originalConstants[target] == nil then
            originalConstants[target] = {}
        end

        if originalConstants[target][name] == nil then
            originalConstants[target][name] = target[name]
        end

        target[name] = newVal
    end

    function SeasonsModUtil.unregisterConstants()
        for target, constants in pairs(originalConstants) do
            for name, const in pairs(constants) do
                target[name] = const
            end
        end
    end

    function SeasonsModUtil.registerTireType(name, coeffs, wetCoeffs)
        table.insert(tireTypes, name)

        WheelsUtil.registerTireType(name, coeffs, wetCoeffs)
    end

    function SeasonsModUtil.unregisterTireTypes()
        for _, name in ipairs(tireTypes) do
            WheelsUtil.unregisterTireType(name)
        end
    end
else
    function SeasonsModUtil.overwrittenFunction(target, name, newFunc)
        target[name] = Utils.overwrittenFunction(target[name], newFunc)
    end

    function SeasonsModUtil.appendedFunction(target, name, newFunc)
        target[name] = Utils.appendedFunction(target[name], newFunc)
    end

    function SeasonsModUtil.prependedFunction(target, name, newFunc)
        target[name] = Utils.prependedFunction(target[name], newFunc)
    end

    function SeasonsModUtil.overwrittenConstant(target, name, newVal)
        target[name] = newVal
    end

    function SeasonsModUtil.overwrittenStaticFunction(target, name, newFunc)
        local oldFunc = target[name]
        target[name] = function (...)
            return newFunc(oldFunc, ...)
        end
    end

    SeasonsModUtil.registerTireType = WheelsUtil.registerTireType
end

---Turn a temperature in celcius into a localized formatted string
function SeasonsModUtil.formatSmallWeight(kilograms, precision, useLongName)
    local weight = kilograms
    if g_i18n.useMiles then
        weight = kilograms * 2.20462
    end
    local str = SeasonsModUtil.getSmallWeightUnit(useLongName)

    if kilograms < 10 then
        precision = math.max(precision or 0, 1)
    end

    return string.format("%1." .. (precision or 0) .. "f %s", weight, str)
end

---Get the temperature unit text
function SeasonsModUtil.getSmallWeightUnit(useLongName)
    local postfix = "Short"
    if useLongName then
        postfix = ""
    end

    if g_i18n.useMiles then
        return g_i18n.texts["seasons_unit_lbs"..postfix]
    end
    return g_i18n.texts["seasons_unit_kg"..postfix]
end

function SeasonsModUtil.formatSex(isFemale)
    return isFemale and g_i18n:getText("seasons_animal_sex_female_short") or g_i18n:getText("seasons_animal_sex_male_short")
end

function SeasonsModUtil.formatAge(age)
    return string.format("%.1f %s", age, g_i18n:getText("seasons_animal_age"))
end
