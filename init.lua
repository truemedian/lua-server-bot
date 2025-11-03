local discordia = require("discordia")
discordia.extensions()

local config = require("./config.lua")
local commands = require("commands.lua")

local client = discordia.Client(config.discordia)

client:on("messageCreate", function(message)
    if not message.guild or message.author.bot then
        return -- ignore dms, self and other bots
    end

    if message.content:startswith(config.prefix) then
        local content = message.content:sub(#config.prefix + 1)
        local cmd = content:match("^%S+")

        if message.channel.id ~= '562456130597552138' then
            local member = message.guild:getMember(message.author)

            if not member or member.highestRole == message.guild.defaultRole then
                return -- don't allow roleless to run outside of #bot-commands
            end
        end

        if cmd then
            local arg = content:sub(#cmd + 1):trim()

            commands.process(message, cmd, arg)
        end
    end
end)

client:run("Bot " .. config.token)
