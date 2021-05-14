local discordia = require('discordia')
local ffi = require('ffi')
local uv = require('uv')
local utf8 = require('utf8')

local runner = require('runner.lua')
local config = require('../config.lua')

local timers = {}
local commands = {}

local function add_command(name, usage, help, fn)
    table.insert(commands, {name = name, usage = usage:trim(), help = help:trim(), fn = fn})
end

timers.uptime = discordia.Stopwatch()
timers.uptime:start()

timers.runner = discordia.Stopwatch()
timers.runner:start()

add_command('run', 'run <source>', [[
Runs lua code from a source. Uses emkc.org's piston api.

Valid Sources:
  - code block
  - gist.github.com
  - pastebin.com
  - paste.gg
  - file
]], function(message, arg)
    if timers.runner:getTime():toMilliseconds() < 250 then
        return message:reply('⚠ too fast')
    else
        timers.runner:reset()
    end

    if message.channel.id ~= '562456130597552138' then
        local member = message.guild:getMember(message.author)

        if not member or member.highestRole == message.guild.defaultRole then
            return -- don't allow roleless to run outside of #bot-commands
        end
    end

    local result, output = runner.run(arg, message.attachment)
    if not result then
        return message:reply('⚠ ' .. output)
    end

    local abridged = nil
    if utf8.len(output) > 2025 then
        abridged = {'output.txt', output}
        output = output:sub(1, utf8.offset(output, 2025)) .. '... [truncated]'
    end

    return message:reply({
        file = abridged,
        embed = {
            title = 'Run Output',
            description = '```\n' .. output .. '```',
            footer = {text = 'Lua ' .. result.version},
        },
    })
end)

local modf, fmod = math.modf, math.fmod

local KB_PER_MB = 1024
local B_PER_KB = 1024

local B_PER_MB = B_PER_KB * KB_PER_MB

local memfmt = '%s MB %s KB %s B'
local function format_memory(mem)
    return memfmt:format(modf(mem / B_PER_MB), modf(fmod(mem / B_PER_KB, KB_PER_MB)), modf(fmod(mem, B_PER_KB)))
end

add_command('info', 'info', [[
Provides information about the current state of the bot. Including uptime, memory usage, and host system
]], function(message, arg)
    local cpus = uv.cpu_info()

    message:reply({
        embed = {
            title = 'Nerd Statistics',
            fields = {
                {inline = true, name = 'Operating System', value = ffi.os},
                {inline = true, name = 'CPU Cores', value = #cpus},
                {inline = true, name = 'CPU Model', value = cpus[1].model},
                {inline = true, name = 'Memory Usage', value = format_memory(collectgarbage 'count')},
                {inline = true, name = 'System Uptime', value = discordia.Time.fromSeconds(uv.uptime()):toString()},
                {inline = true, name = 'Bot Uptime', value = timers.uptime:getTime():toString()},
            },
        },
    })
end)

add_command('help', 'help', [[
Provides information about commands possible using the bot.
]], function(message, arg)
    local cmds = {}

    local longest_usage = 0

    for _, tbl in ipairs(commands) do
        longest_usage = math.max(longest_usage, #tbl.usage)
    end

    for _, tbl in ipairs(commands) do
        table.insert(cmds, config.prefix .. tbl.usage:pad(longest_usage + 3) .. tbl.help)
    end

    message:reply('```' .. table.concat(cmds, '\n\n') .. '```')
end)

local function process(message, cmd, arg)
    for _, tbl in ipairs(commands) do
        if tbl.name == cmd:lower() then
            tbl.fn(message, arg)
        end
    end
end

return {process = process}
