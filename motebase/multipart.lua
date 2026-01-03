local multipart = {}

function multipart.get_boundary(content_type)
    if not content_type then return nil end
    local boundary = content_type:match("boundary=([^;]+)")
    if boundary then return boundary:gsub('^"', ""):gsub('"$', "") end
    return nil
end

function multipart.is_multipart(content_type)
    return content_type and content_type:match("^multipart/form%-data") ~= nil
end

local function parse_disposition(header)
    return {
        name = header:match('name="([^"]+)"'),
        filename = header:match('filename="([^"]*)"'),
    }
end

local function parse_part_headers(header_section)
    local headers = {}
    for line in header_section:gmatch("[^\r\n]+") do
        local name, value = line:match("^([^:]+):%s*(.+)$")
        if name then headers[name:lower()] = value end
    end
    return headers
end

function multipart.parse(body, boundary)
    if not body or not boundary then return nil, "missing body or boundary" end

    local parts = {}
    local delimiter = "--" .. boundary
    local end_delimiter = "--" .. boundary .. "--"

    local pos = 1
    local part_start = body:find(delimiter, pos, true)

    if not part_start then return nil, "no parts found" end

    while true do
        pos = part_start + #delimiter

        if body:sub(pos, pos + 1) == "\r\n" then
            pos = pos + 2
        elseif body:sub(pos, pos) == "\n" then
            pos = pos + 1
        end

        if body:sub(part_start, part_start + #end_delimiter - 1) == end_delimiter then break end

        local next_part = body:find(delimiter, pos, true)
        if not next_part then break end

        local part_content = body:sub(pos, next_part - 1)
        part_content = part_content:gsub("\r\n$", ""):gsub("\n$", "")

        local header_end = part_content:find("\r\n\r\n", 1, true)
        local header_sep_len = 4
        if not header_end then
            header_end = part_content:find("\n\n", 1, true)
            header_sep_len = 2
        end

        if header_end then
            local header_section = part_content:sub(1, header_end - 1)
            local part_body = part_content:sub(header_end + header_sep_len)

            local headers = parse_part_headers(header_section)
            local disposition = headers["content-disposition"]

            if disposition then
                local info = parse_disposition(disposition)
                local part = {
                    name = info.name,
                    filename = info.filename,
                    content_type = headers["content-type"] or "text/plain",
                    data = part_body,
                }

                if info.name then parts[info.name] = part end
            end
        end

        part_start = next_part
    end

    return parts
end

function multipart.is_file(part)
    return part and part.filename and part.filename ~= ""
end

return multipart
