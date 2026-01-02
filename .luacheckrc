std = "lua51+lua52+lua53+lua54"
max_line_length = false

include_files = {
    "motebase/**/*.lua",
    "bin/**/*.lua",
    "spec/**/*.lua",
}

files["spec/**/*.lua"] = {
    std = "+busted",
}
