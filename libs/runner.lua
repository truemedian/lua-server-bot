local http = require('coro-http')
local lpeg = require('lpeg')
local json = require('json')
local uv = require('uv')

local function format_http_error(url, res, masked)
    return masked and ('<%s>: %d %s'):format(url, res.code, res.reason) or
               ('%s: %d %s'):format(url, res.code, res.reason)
end

local function fetch(url)
    local head, body = http.request('GET', url, {{'Accept', 'application/octet-stream'}})

    if head.code == 200 then
        return body
    else
        return nil, format_http_error(url, head, true)
    end
end

local execute_api = 'https://emkc.org/api/v2/piston/execute'

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

local function run(arg, attachment)
    local source, err

    if arg:startswith('```') then
        source = arg:match('^```[^\n]*\n(.+)```') or arg:match('^```(.+)```')
    elseif arg:startswith('`') then
        source = arg:match('^`([^`]+)`')
    elseif arg:startswith('http') then
        if pastebin_com:match(arg) then
            local blob = pastebin_com:match(arg)
            source, err = fetch(pastebin_com_url:format(blob))
        elseif paste_gg:match(arg) then
            local author, paste, blob = paste_gg:match(arg)

            source, err = fetch(paste_gg_url:format(author, paste, blob))
        elseif gist_github_com:match(arg) then
            local author, hash, blob = gist_github_com:match(arg)
            source, err = fetch(gist_github_com_url:format(author, hash, blob or ''))
        end
    elseif attachment then
        source, err = fetch(attachment.url)
    end

    if not source then
        if not err then
            err = 'could not find source'
        end

        return nil, err
    end

    local payload = json.encode({
        language = 'lua',
        version = '5.4',
        files = {{name = 'main.lua', content = source}},
        run_timeout = 10000,
        run_memory_limit = -1,
    })

    local start = uv.hrtime()
    local head, res = http.request('POST', execute_api, {{'Content-Type', 'application/json'}}, payload)
    local stop = uv.hrtime()

    if head.code ~= 200 then
        return nil, format_http_error('execute', head)
    end

    local result = json.decode(res)

    if result.message then
        return nil, result.message
    end

    if result.run then
        local output = result.run.output

        if #output == 0 then
            output = 'No Output'
        end

        local death = 'Killed'
        if result.run.code then
            death = 'Exited: ' .. result.run.code
        elseif result.run.signal then
            death = 'Killed: ' .. result.run.signal
        end

        death = string.format('%s in %d ms', death, (stop - start) / 1e6)

        return death, output, result.version
    else
        return nil, 'An unknown error occurred.'
    end
end

return {run = run}
