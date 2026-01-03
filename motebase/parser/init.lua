local parser = {}

parser.email = require("motebase.parser.email")
parser.http = require("motebase.parser.http")
parser.multipart = require("motebase.parser.multipart")
parser.primitives = require("motebase.parser.primitives")

return parser
