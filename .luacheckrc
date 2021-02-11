redefined = false
include_files = {
    '*.lua',
    'test/**/*.lua',
    'graphql/**/*.lua',
    '*.rockspec',
    '.luacheckrc',
}
exclude_files = {
    '.rocks',
}
new_read_globals = {
    box = { fields = {
        session = { fields = {
            storage = {read_only = false, other_fields = true}
        }}
    }}
}
