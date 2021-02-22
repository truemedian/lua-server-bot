local discordia = require('discordia')
local http = require('coro-http')
local lpeg = require('lpeg')
local json = require('json')
discordia.extensions()

local config = require('./config.lua')
local client = discordia.Client(config.discordia)

local modf, fmod = math.modf, math.fmod

local function fetch(url)
    local head, body = http.request('GET', url, {{'Accept', 'application/octet-stream'}})

    if head.code == 200 then
        return body
    else
        return nil, head.code .. ' ' .. head.reason
    end
end

local emkc_piston = 'https://emkc.org/api/v1/piston/execute'

lpeg.locale(lpeg)

local pastebin_com, paste_gg, gist_github_com
local pastebin_com_url, paste_gg_url, gist_github_com_url
do
    local P, C = lpeg.P, lpeg.C

    local function opt(patt)
        return P(patt) ^ -1
    end

    local function masked(patt)
        return (P('<') * P(patt) * P('>')) + P(patt)
    end

    local https = P('http') * opt('s') * P('://')
    local author = lpeg.alnum ^ 1
    local hash = lpeg.alnum ^ 1

    pastebin_com = masked(https * P('pastebin.com/') * ((P('raw/') * C(author)) + C(hash)))
    pastebin_com_url = 'https://pastebin.com/raw/%s'

    paste_gg = masked(https * P('paste.gg/p/') * C(author) * P('/') * C(hash) * P('/files/') * C(hash) * opt('/raw'))
    paste_gg_url = 'https://paste.gg/p/%s/%s/files/%s/raw'

    local gist_short = P('gist.github.com/') * C(author) * P('/') * C(hash)
    local gist_long = P('gist.githubusercontent.com/') * C(author) * P('/') * C(hash) *
                          opt(P('/raw') * opt(P('/' * C(hash))))
    gist_github_com = masked(https * (gist_long + gist_short))
    gist_github_com_url = 'https://gist.githubusercontent.com/%s/%s/raw/%s'
end

local uptime = discordia.Stopwatch()
uptime:start()

local runner_timeout = discordia.Stopwatch()
runner_timeout:start()

local correction_timeout = discordia.Stopwatch()
correction_timeout:start()

local usage = [[```
&run [source]   Runs lua code from source. Uses emkc.org's piston api.

Valid Sources:
  - code block
  - gist.github.com
  - pastebin.com
  - paste.gg
  - file
```]]

local info = [[
Uptime: %s
Memory: %s
]]

local KB_PER_MB = 1024
local B_PER_KB = 1024

local B_PER_MB = B_PER_KB * KB_PER_MB

local memfmt = '%s MB %s KB %s B'
local function format_memory(mem)
    return memfmt:format(modf(mem / B_PER_MB), modf(fmod(mem / B_PER_KB, KB_PER_MB)), modf(fmod(mem, B_PER_KB)))
end

client:on('messageCreate', function(message)
    if not message.guild or message.author.bot then
        return -- ignore dms, self and other bots
    end

    if message.content:startswith(config.prefix) then
        local content = message.content:sub(#config.prefix + 1)
        local cmd = content:match('^%S+')

        if cmd then
            local args = content:sub(#cmd + 1):trim()

            if cmd == 'help' then
                message:reply(usage)
            elseif cmd == 'info' then
                local bytes = collectgarbage('count') * 1024

                local time = uptime:getTime():toString()
                local memory = format_memory(bytes)

                message:reply(info:format(time, memory))
            elseif cmd == 'run' then
                if runner_timeout:getTime():toMilliseconds() < 250 then
                    return message:reply('⚠ too fast')
                else
                    runner_timeout:reset()
                end

                local source

                if message.channel.id ~= '562456130597552138' then
                    local member = message.guild:getMember(message.author)

                    if member.highestRole == message.guild.defaultRole then
                        return -- don't allow roleless to run outside of #bot-commands
                    end
                end

                local err
                if args:startswith('```') then
                    source = args:match('^```[^\n]*\n(.+)```') or args:match('^```(.+)```')
                elseif args:startswith('http') then
                    if pastebin_com:match(args) then
                        local blob = pastebin_com:match(args)
                        source, err = fetch(pastebin_com_url:format(blob))
                    elseif paste_gg:match(args) then
                        local author, paste, blob = paste_gg:match(args)

                        source, err = fetch(paste_gg_url:format(author, paste, blob))
                    elseif gist_github_com:match(args) then
                        local author, hash, blob = gist_github_com:match(args)
                        source, err = fetch(gist_github_com_url:format(author, hash, blob or ''))
                    end
                elseif message.attachment then
                    source, err = fetch(message.attachment.url)
                end

                if not source then
                    if not err then
                        err = 'could not find source'
                    end

                    return message:reply('⚠ ' .. err)
                end

                local payload = json.encode({language = 'lua', source = source})
                local head, res = http.request('POST', emkc_piston, {{'Content-Type', 'application/json'}}, payload)

                if head.code ~= 200 then
                    return message:reply('⚠ ' .. head.code .. ' ' .. head.reason)
                end

                local result = json.decode(res)
                local output

                if #result.stdout == 0 then
                    if #result.stderr == 0 then
                        output = 'No Output'
                    else
                        output = result.stderr
                    end
                else
                    output = result.stdout
                end

                local abridged = nil
                if #output > 2025 then
                    abridged = {'output.txt', output}
                    output = output:sub(1, 2025) .. '... [truncated]'
                end

                return message:reply({
                    file = abridged,
                    embed = {
                        title = 'Run Output',
                        description = '```' .. output .. '```',
                        footer = {text = 'Lua ' .. result.version},
                    },
                })
            end
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
