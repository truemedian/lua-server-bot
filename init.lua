local discordia = require('discordia')
discordia.extensions()

local config = require('./config.lua')
local commands = require('commands.lua')

local client = discordia.Client(config.discordia)

local correction_timeout = discordia.Stopwatch()
correction_timeout:start()

local correction_autoresponse =
    [[> "Lua" (pronounced LOO-ah) means "Moon" in Portuguese. As such, it is neither an acronym nor an abbreviation, but a noun. More specifically, "Lua" is a name, the name of the Earth's moon and the name of the language. Like most names, it should be written in lower case with an initial capital, that is, "Lua". **Please do not write it as "LUA"**, which is both ugly and confusing, because then it becomes an acronym with different meanings for different people. So, please, write "Lua" right! - https://www.lua.org/about.html]]

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
    elseif (message.content:find('%WLUA%W') or message.content:startswith('LUA') or message.content:endswith('LUA')) and not message.content:find('LUA_', 1, true) then
        if correction_timeout:getTime():toMinutes() > 15 then
            local previous_messages = message.channel:getMessages(40)
            local has_correction = previous_messages:find(function(m)
                return m.author == client.user and m.content == correction_autoresponse
            end)

            if not has_correction then
                correction_timeout:reset()

                message:reply(correction_autoresponse)
            end
        end
    end
end)

-- local list = {
--     'test'
-- }

-- client:on('ready', function()
--     local guild = client:getGuild('385257136051191808')
--     local report = guild:getChannel('468172073617850388')

--     local total = 0
--     local total_count = 0

--     local authors = {}

--     for channel in guild.textChannels:iter() do
--         local last_message = channel:getLastMessage()

--         local start = os.time()

--         local n = 0
--         local count = 0

--         if last_message then
--             count = count + 1

--             for _, text in ipairs(list) do
--                 local content = ' ' .. last_message.content:lower() .. ' '
--                 if content:find('%W' .. text .. '%W') then
--                     last_message:delete()

--                     authors[last_message.author.id] = authors[last_message.author.id] or 0
--                     authors[last_message.author.id] = authors[last_message.author.id] + 1

--                     n = n + 1
--                 end
--             end
--         end

--         while last_message do
--             local messages = channel:getMessagesBefore(last_message, 100):toArray('id')

--             if #messages == 0 then break end

--             last_message = messages[1]

--             for _, message in ipairs(messages) do
--                 count = count + 1

--                 for _, text in ipairs(list) do
--                     local content = ' ' .. message.content:lower() .. ' '
--                     if content:find('%W' .. text .. '%W') then
--                         message:delete()

--                         authors[message.author.id] = authors[message.author.id] or 0
--                         authors[message.author.id] = authors[message.author.id] + 1

--                         n = n + 1
--                     end
--                 end
--             end
--         end

--         local stop = os.time()
--         report:send(tostring(n) ..  ' messages deleted from #' .. channel.name .. ' in ' .. tostring(stop - start) .. ' seconds (' .. count .. ' messages)')

--         total = total + n
--     end

--     local all_authors = {}
--     for id, n in pairs(authors) do
--         table.insert(all_authors, '<@' .. id .. '> - ' .. n)
--     end

--     report:send(tostring(total) ..  ' messages deleted. (of ' .. total_count .. ' total messages) finished.\n' .. table.concat(all_authors, '\n'))
-- end)

client:run('Bot ' .. config.token)
