local discordia = require('discordia')
discordia.extensions()

local config = require('./config.lua')
local commands = require('commands.lua')

local client = discordia.Client(config.discordia)

local correction_timeout = discordia.Stopwatch()
correction_timeout:start()

client:on('messageCreate', function(message)
    if not message.guild or message.author.bot then
        return -- ignore dms, self and other bots
    end

    if message.content:startswith(config.prefix) then
        local content = message.content:sub(#config.prefix + 1)
        local cmd = content:match('^%S+')

        if cmd then
            local arg = content:sub(#cmd + 1):trim()

            commands.process(message, cmd, arg)
        end
    elseif message.content:find('%WLUA%W', 1) or message.content:startswith('LUA') or message.content:endswith('LUA') then
        if correction_timeout:getTime():toMinutes() > 2 then
            correction_timeout:reset()

            message:reply(
                [[> "Lua" (pronounced LOO-ah) means "Moon" in Portuguese. As such, it is neither an acronym nor an abbreviation, but a noun. More specifically, "Lua" is a name, the name of the Earth's moon and the name of the language. Like most names, it should be written in lower case with an initial capital, that is, "Lua". **Please do not write it as "LUA"**, which is both ugly and confusing, because then it becomes an acronym with different meanings for different people. So, please, write "Lua" right! - https://www.lua.org/about.html]])
        end
    end
end)

client:run('Bot ' .. config.token)
