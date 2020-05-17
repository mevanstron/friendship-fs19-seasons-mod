----------------------------------------------------------------------------------------------------
-- SeasonsMessageType
----------------------------------------------------------------------------------------------------
-- Purpose:  Struct with message IDs for local notifications.
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsMessageType = {}
getfenv(0)["SeasonsMessageType"] = SeasonsMessageType -- Make usable by other mods

---The season changed.
SeasonsMessageType.SEASON_CHANGED = nextMessageTypeId() -- (season)

---The visual season changed.
SeasonsMessageType.VISUAL_SEASON_CHANGED = nextMessageTypeId() -- (visualSeason)

---Period changed.
SeasonsMessageType.PERIOD_CHANGED = nextMessageTypeId() -- (period)

---Year changed.
SeasonsMessageType.YEAR_CHANGED = nextMessageTypeId() -- (year)

---Hour changed, but with the currentDay correct on new days.
SeasonsMessageType.HOUR_CHANGED_FIX = nextMessageTypeId() -- (hour)

---Length of the seasons changed.
SeasonsMessageType.SEASON_LENGTH_CHANGED = nextMessageTypeId() -- (length)

---Weather changed
SeasonsMessageType.WEATHER_CHANGED = nextMessageTypeId()

---Change in freezing/not freezing temperature of either air or soil
SeasonsMessageType.FREEZING_CHANGED = nextMessageTypeId()

---Change in height of snow (visually)
SeasonsMessageType.SNOW_HEIGHT_CHANGED = nextMessageTypeId()

---A vehicle was repaired
SeasonsMessageType.VEHICLE_REPAINTED = nextMessageTypeId() -- (vehicle, atSellingPoint)

---A pump was added
SeasonsMessageType.WATER_PUMP_ADDED = nextMessageTypeId() -- (pump)

---A pump was removed
SeasonsMessageType.WATER_PUMP_REMOVED = nextMessageTypeId() -- (pump)

---Daylight values changed
SeasonsMessageType.DAYLIGHT_CHANGED = nextMessageTypeId()
