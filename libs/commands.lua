local discordia = require('discordia')
local ffi = require('ffi')
local uv = require('uv')
local utf8 = require('utf8')

local runner = require('runner.lua')
local config = require('../config.lua')

local timers = {}
local commands = {}

local function add_command(name, usage, help, fn, hide)
    table.insert(commands, {name = name, usage = usage:trim(), help = help:trim(), fn = fn, hide = hide})
end

timers.uptime = discordia.Stopwatch()
timers.uptime:start()

timers.runner = discordia.Stopwatch()
timers.runner:start()

add_command('run', 'run [5.x] <source>', [[
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

    local result, output, version = runner.run(arg, message.attachment)
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
            footer = {text = result},
            author = {name = 'Lua ' .. version, icon_url = message.client.user.avatarURL},
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
		if not tbl.hide then
			longest_usage = math.max(longest_usage, #tbl.usage)
		end
	end

    for _, tbl in ipairs(commands) do
        if not tbl.hide then
			table.insert(cmds, config.prefix .. tbl.usage:pad(longest_usage + 3) .. tbl.help)
		end
	end

    message:reply('```' .. table.concat(cmds, '\n\n') .. '```')
end)

local function subsequence_match(subseq, str)
    local matches = 0

    for i = 1, #str do
        if string.byte(subseq, matches + 1) == string.byte(str, i) then
            matches = matches + 1
        end
    end

    return matches == #subseq
end

local function subsequences(start, prefix, str, left)
    if left == 0 then
        coroutine.yield(prefix)
    else
        for i = start, #str do
            subsequences(i + 1, prefix .. str:sub(i, i), str, left - 1)
        end
    end
end

add_command('member', 'member <user>', [[
Provides information about a member. If no user is provided, will provide information about the message author.
]], function(message, arg)
	local user = arg:match('<@!?(%d+)>') or arg

	if not user then
		user = message.author
	else
		user = message.guild:getMember(user)
	end

	if not user then
		return message:reply('⚠ user not found')
	end

    local smallest = ''
    for n = 1, #user.username do
        local iter = coroutine.wrap(function() subsequences(1, '', user.username, n) end)
        for s in iter do
            local found = false

            for check in message.guild.members:iter() do
                if check ~= user and subsequence_match(s, check.username) then
                    found = true
                    break
                end
            end

            if not found then
                smallest = s
                break
            end
        end

        if smallest ~= '' then
            break
        end
    end

    if smallest == '' then
        smallest = user.username
    end

	message:reply(string.format('```\n%s %s\n@%s\n```', user.username, user.id, smallest))
end)

add_command('exec', 'exec', [[]], function(message, arg)
	if message.author ~= message.client.owner then
		return
	end

	local source

	if arg:sub(1, 3) == '```' then
		source = arg:match('```%S*(.*)```')
	else
		source = arg
	end

	if not source then
		return message:reply('⚠  no source')
	end

	local lines = {}
	local function env_print(...)
		local t = {}
		for i = 1, select('#', ...) do
			t[i] = tostring(select(i, ...))
		end
		table.insert(lines, table.concat(t, '\t'))
	end

	local env = setmetatable({
		message = message,
		guild = message.guild,
		author = message.author,

		discordia = discordia,
		client = message.client,

		print = env_print,
	}, { __index = _G })

	local fn, err = load(source, '=discord', 't', env)
	if not fn then
		return message:reply('⚠  ```\n' .. err .. '```')
	end

	local success, ret = pcall(fn)
	if not success then
		return message:reply('⚠  ```\n' .. ret .. '```')
	end

	if ret ~= nil then
		env_print(ret)
	end

	local out = table.concat(lines, '\n')
	if #out > 0 then
		return message:reply('```\n' .. out .. '```')
	end
end, true)

local function process(message, cmd, arg)
    for _, tbl in ipairs(commands) do
        if tbl.name == cmd:lower() then
            tbl.fn(message, arg)
        end
    end
end

return {process = process}
