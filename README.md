# Flow inspector

A probably buggy[^1] inspector for flow GUIs to help with debugging layouting.

[^1]: I'm not really happy with how hacky this mod is but it works.

## Usage

 - `/inspector`: Toggles the inspector for all flow forms opened with
    `form:show()`.

### Hot reload

When the "hot reload" button is pressed, the server reloads the file containing
the function passed to `flow.make_gui`. This file must have exactly one
`flow.make_gui` call for hot reload to work. Existing values in `ctx` are
preserved when hot reloading.

The file containing `flow.make_gui` shouldn't contain any registrations (for
example `minetest.register_globalstep`) as it may result in them being
registered multiple times.

### Open debug shell

If you're running Minetest in a terminal, an "open debug shell" button will
be shown which will call `debug.debug()` (or `dbg.dd()` if the dbg mod is
installed) when pressed. `player`, `ctx`, and `name` variables are set when the
debug shell is open.

## API

 - `flow_inspector.enable(player)`: Enables the inspector.
 - `flow_inspector.disable(player)`: Disables the inspector.
 - `flow_inspector.inspect(player, form)`: Opens the inspector for `form`.

## License

Code: LGPL v3.0+

Textures (flow_inspector_bg.png, flow_inspector_padding.png, and
flow_inspector_selection.png): CC-0
