max_line_length = 80

globals = {
    'core',
    'flow_inspector',
    'flow',
}

read_globals = {
    'DIR_DELIM',
    'formspec_ast',
    'hud_fs',
    'dump',
    'dbg',
    string = {fields = {'split', 'trim'}},
    table = {fields = {'copy', 'indexof'}}
}

-- This error is thrown for methods that don't use the implicit "self"
-- parameter.
ignore = {"212/self", "432/player", "43/ctx", "212/player", "212/ctx"}
