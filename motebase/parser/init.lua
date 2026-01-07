-- Parser Module Aggregator

local parser = {}

parser.core = require("motebase.parser.core")
parser.email = require("motebase.parser.email")
parser.http = require("motebase.parser.http")
parser.ip = require("motebase.parser.ip")
parser.mime = require("motebase.parser.mime")
parser.multipart = require("motebase.parser.multipart")
parser.uri = require("motebase.parser.uri")

return parser
