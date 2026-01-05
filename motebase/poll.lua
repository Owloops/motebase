local poll_c = require("motebase.poll_c")

local poll = {}

poll._MAXFDS = poll_c._MAXFDS
poll.poll = poll_c.poll
poll.select = poll_c.select

return poll
