local smtp = require("socket.smtp")

local mail = {}

-- config --

local config = {
    host = os.getenv("MOTEBASE_SMTP_HOST"),
    port = tonumber(os.getenv("MOTEBASE_SMTP_PORT")) or 587,
    user = os.getenv("MOTEBASE_SMTP_USER"),
    pass = os.getenv("MOTEBASE_SMTP_PASS"),
    from = os.getenv("MOTEBASE_SMTP_FROM"),
}

-- helpers --

local function is_configured()
    return config.host and config.user and config.pass and config.from
end

-- public --

function mail.configure(cfg)
    if cfg.host then config.host = cfg.host end
    if cfg.port then config.port = cfg.port end
    if cfg.user then config.user = cfg.user end
    if cfg.pass then config.pass = cfg.pass end
    if cfg.from then config.from = cfg.from end
end

function mail.is_enabled()
    return is_configured()
end

function mail.send(to, subject, body)
    if not is_configured() then return nil, "SMTP not configured" end

    local result, err = smtp.send({
        from = "<" .. config.from .. ">",
        rcpt = "<" .. to .. ">",
        source = smtp.message({
            headers = {
                from = config.from,
                to = to,
                subject = subject,
                ["content-type"] = "text/html; charset=utf-8",
            },
            body = body,
        }),
        server = config.host,
        port = config.port,
        user = config.user,
        password = config.pass,
    })

    if not result then return nil, err end

    return true
end

-- templates --

function mail.send_password_reset(to, token, app_url)
    local subject = "Password Reset Request"
    local reset_url = app_url .. "/reset-password?token=" .. token

    local body = [[
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: sans-serif; padding: 20px;">
    <h2>Password Reset</h2>
    <p>You requested a password reset. Click the link below to set a new password:</p>
    <p><a href="]] .. reset_url .. [[">Reset Password</a></p>
    <p>Or copy this link: ]] .. reset_url .. [[</p>
    <p>This link expires in 1 hour.</p>
    <p>If you didn't request this, ignore this email.</p>
</body>
</html>
]]

    return mail.send(to, subject, body)
end

function mail.send_verification(to, token, app_url)
    local subject = "Verify Your Email"
    local verify_url = app_url .. "/verify-email?token=" .. token

    local body = [[
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: sans-serif; padding: 20px;">
    <h2>Email Verification</h2>
    <p>Please verify your email address by clicking the link below:</p>
    <p><a href="]] .. verify_url .. [[">Verify Email</a></p>
    <p>Or copy this link: ]] .. verify_url .. [[</p>
    <p>This link expires in 24 hours.</p>
</body>
</html>
]]

    return mail.send(to, subject, body)
end

return mail
