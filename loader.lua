--[[============================================================================
    AdoptMe Trade Bot - loader
    ----------------------------------------------------------------------------
    Same idea as the AdoptMe Farm loader: pull the main module, run it, and if
    anything explodes on startup leave a readable error behind.

    Put the raw URL of AdoptMeTradeBot.lua below.
============================================================================]]

local URL = "https://raw.githubusercontent.com/azeroygit/s/main/AdoptMeTradeBot.lua"

local FOLDER = "AdoptMeTradeBot"
local ERROR_FILE = FOLDER .. "/start_error.txt"

local function ensureFolder()
    if isfolder and makefolder then
        if not isfolder(FOLDER) then
            pcall(makefolder, FOLDER)
        end
    end
end

local function writeError(text)
    if writefile then
        pcall(writefile, ERROR_FILE, text)
    end
end

local ok, err = pcall(function()
    ensureFolder()

    local source = game:HttpGet(URL)
    if not source or #source < 200 then
        error("downloaded source looks empty (" .. tostring(source and #source) .. " bytes)")
    end

    local chunk, compileError = loadstring(source)
    if not chunk then
        error("compile error: " .. tostring(compileError))
    end

    chunk()
end)

if ok then
    writeError("started " .. os.date("%Y-%m-%d %H:%M:%S"))
else
    local text = table.concat({
        "AdoptMe Trade Bot loader error",
        os.date("%Y-%m-%d %H:%M:%S"),
        "",
        tostring(err),
        "",
        debug.traceback(),
    }, "\n")
    writeError(text)
    warn("[AdoptMeTradeBot] " .. tostring(err))
end
