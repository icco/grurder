-- norns globals (set by script, called by the runtime)
globals = {
  "init",
  "cleanup",
  "redraw",
  "key",
  "enc",
}

read_globals = {
  "clock",
  "metro",
  "midi",
  "os",
  "params",
  "screen",
  "table",
  "util",
  "norns",
  "math",
  "string",
}

allow_defined_top = true
max_line_length = false

-- norns callbacks are set but invoked by the runtime
ignore = {"131"}
