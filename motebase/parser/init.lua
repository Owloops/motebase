local parser = {}

parser.abnf = require("motebase.parser.abnf")
parser.email = require("motebase.parser.email")
parser.http = require("motebase.parser.http")
parser.ih = require("motebase.parser.ih")
parser.ip = require("motebase.parser.ip")
parser.mime = require("motebase.parser.mime")
parser.multipart = require("motebase.parser.multipart")
parser.url = require("motebase.parser.url")

return parser
