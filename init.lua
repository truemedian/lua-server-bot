local discordia = require("discordia")
discordia.extensions()

local config = require("./config.lua")
local commands = require("commands.lua")

local client = discordia.Client(config.discordia)

local fs = require("fs")
local banlist_fd = assert(fs.openSync('banlist.txt', 'a'))

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

    if message.channel.id == '1507820139960209479' then
        if message.guild:banUser(message.author.id, 'auto-kick', 1) then
            if not message.guild:unbanUser(message.author.id, 'auto-kick') then
                client:getChannel('939400077569572894'):send('⚠ failed to unban <@' .. message.author.id .. '>')
            end

            client:getChannel('939400077569572894'):send('<#1507820139960209479> soft-banned <@' .. message.author.id .. '>')
            fs.writeSync(banlist_fd, message.author.id .. '\n')
        end
    end
end)

client:run("Bot " .. config.token)
