----------------------------------------------------------------------------------------------------
-- SeasonsMathUtil
----------------------------------------------------------------------------------------------------
-- Purpose:  Math utilities
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsMathUtil = {}

--Outputs a random sample from a triangular distribution
function SeasonsMathUtil.triDist(min, mode, max)
    local pmode = {}
    local p = {}

    pmode = (mode - min) / (max - min)
    p = math.random()
    if p < pmode then
        return math.sqrt(p * (max - min) * (mode - min)) + min
    else
        return max - math.sqrt((1 - p) * (max - min) * (max - mode))
    end
end

-- Approximation of the inverse CFD of a normal distribution
-- Based on A&S formula 26.2.23 - thanks to John D. Cook
function SeasonsMathUtil.rationalApproximation(t)
    local c = {2.515517, 0.802853, 0.010328}
    local d = {1.432788, 0.189269, 0.001308}

    return t - ((c[3] * t + c[2]) * t + c[1]) / (((d[3] * t + d[2]) * t + d[1]) * t + 1.0)
end

-- Outputs a random sample from a normal distribution with mean mu and standard deviation sigma
function SeasonsMathUtil.normDist(mu, sigma)
    local p = math.random()

    if p < 0.5 then
        return SeasonsMathUtil.rationalApproximation(math.sqrt(-2.0 * math.log(p))) * -sigma + mu
    else
        return SeasonsMathUtil.rationalApproximation(math.sqrt(-2.0 * math.log(1 - p))) * sigma + mu
    end
end

function SeasonsMathUtil.normCDF(x, mu, sigma)
    x = (x - mu) / (sigma * math.sqrt(2))

    return 0.5 * (1 + SeasonsMathUtil.erf(x))
end

-- Approximation of the error function
-- Based on A&S formula 7.1.26 - thanks to John D. Cook
function SeasonsMathUtil.erf(x)
    local a = {0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429}
    local p = 0.3275911

    local sign = 1
    if x < 0 then
        sign = -1
    end
    x = math.abs(x)

    local t = 1 / (1 + p * x)
    local y = 1 - (((((a[5] * t + a[4]) * t) + a[3]) * t + a[2]) * t + a[1]) * t * math.exp(-x * x)

    return sign * y
end

-- Outputs a random sample from a lognormal distribution
function SeasonsMathUtil.lognormDist(beta, gamma)
    local p = math.random()
    local z

    if p < 0.5 then
        z = SeasonsMathUtil.rationalApproximation( math.sqrt(-2.0 * math.log(p))) * -1
    else
        z = SeasonsMathUtil.rationalApproximation( math.sqrt(-2.0 * math.log(1 - p)))
    end

    return gamma * math.exp ( z / beta )
end

-- Outputs a random float between min and max values
function SeasonsMathUtil.random(min, max)
    return min + math.random()  * (max - min)
end

function SeasonsMathUtil.truncate(value, decimals)
    local m = math.pow(10, decimals)

    return math.floor(value * m) / m
end
