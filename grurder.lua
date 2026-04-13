-- grurder
-- @icco
--
-- generative midi sequencer
-- euclidean rhythms + turing machine
--
-- 8mu faders control generation
-- outputs two voices to mmMidi
--
-- E1 tempo  E2 octave  E3 root
-- K2 page   K3 reset/random (short/long)
-- 8mu faders 1-4: seq1 (steps/pulses/rot/prob)
-- 8mu faders 5-8: seq2 (steps/pulses/rot/prob)

local util = require "util"

-- scales as semitone intervals from root
local scales = {
  {0, 2, 4, 5, 7, 9, 11},     -- major
  {0, 2, 3, 5, 7, 8, 10},     -- minor
  {0, 2, 4, 7, 9},            -- major pentatonic
  {0, 2, 3, 5, 7},            -- minor pentatonic
  {0, 2, 3, 5, 7, 9, 10},    -- dorian
  {0, 1, 3, 5, 7, 8, 10},    -- phrygian
  {0, 2, 4, 6, 7, 9, 11},    -- lydian
  {0, 2, 4, 5, 7, 9, 10},    -- mixolydian
}

local scale_names = {
  "maj", "min", "M.pent", "m.pent",
  "dor", "phry", "lyd", "mixo"
}

local note_names = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

-- state
local midi_in_dev = nil -- luacheck: no unused
local midi_out_dev = nil
local page = 1
local cc = {0, 0, 0, 0, 0, 0, 0, 0}
local redraw_metro = nil
local seq_clock = nil
local k3_held = false

local scale_idx = 1
local root = 0
local octave_range = 2
local tempo = 120

-- per-sequence parameters (indexed 1=seq1, 2=seq2)
local step_count = {8, 8}
local pulse_count = {5, 5}
local rotation = {0, 0}
local flip_prob = {0.0, 0.0}

local seq = {
  {
    pattern = {},
    register = 0,
    pos = 0,
    last_note = nil,
    mute = false,
    history = {},
  },
  {
    pattern = {},
    register = 0,
    pos = 0,
    last_note = nil,
    mute = false,
    history = {},
  },
}


-- bjorklund algorithm
-- attempt to evenly distribute pulses across steps
-- see: Toussaint (2005) "The Euclidean Algorithm Generates Traditional Musical Rhythms"

function bjorklund(steps, pulses)
  if pulses >= steps then
    local p = {}
    for i = 1, steps do p[i] = true end
    return p
  end
  if pulses <= 0 then
    local p = {}
    for i = 1, steps do p[i] = false end
    return p
  end

  local groups = {}
  for i = 1, steps do
    if i <= pulses then
      groups[i] = {true}
    else
      groups[i] = {false}
    end
  end

  while true do
    local remainder = #groups - pulses
    if remainder <= 1 then break end
    local new_groups = {}
    local merge_count = math.min(pulses, remainder)
    for i = 1, merge_count do
      local g = {}
      for _, v in ipairs(groups[i]) do g[#g + 1] = v end
      for _, v in ipairs(groups[#groups - merge_count + i]) do g[#g + 1] = v end
      new_groups[i] = g
    end
    -- leftover groups that weren't merged
    if pulses > remainder then
      for i = merge_count + 1, pulses do
        new_groups[#new_groups + 1] = groups[i]
      end
    end
    groups = new_groups
    pulses = merge_count
  end

  local result = {}
  for _, g in ipairs(groups) do
    for _, v in ipairs(g) do
      result[#result + 1] = v
    end
  end
  return result
end

function rotate_pattern(pattern, offset)
  local n = #pattern
  if n == 0 then return pattern end
  local r = {}
  for i = 1, n do
    local src = ((i - 1 + offset) % n) + 1
    r[i] = pattern[src]
  end
  return r
end


-- shift register / turing machine
-- 16-bit register evolves each step: shift right, conditionally flip the
-- wrapping bit. at probability 0 the pattern locks; at 1 it's fully random.
-- see: Tom Whitwell / Music Thing Modular "Turing Machine"

function shift_register_step(reg, prob)
  local high_bit = reg & 1
  reg = reg >> 1
  if math.random() < prob then
    high_bit = 1 - high_bit
  end
  reg = reg | (high_bit << 15)
  return reg
end

function register_to_note(reg, scale_tbl, root_note, oct_range)
  local deg = (reg % #scale_tbl) + 1
  local interval = scale_tbl[deg]
  local oct = math.floor((reg / #scale_tbl) % oct_range)
  return root_note + 36 + interval + (oct * 12)
end


-- pattern computation

function recompute_pattern(n)
  local p = bjorklund(step_count[n], pulse_count[n])
  seq[n].pattern = rotate_pattern(p, rotation[n])
end

function recompute_patterns()
  recompute_pattern(1)
  recompute_pattern(2)
end


-- midi input handler

function handle_midi(data)
  local msg = midi.to_msg(data)

  if msg.type == "cc" then
    local idx = msg.cc - 33
    if idx >= 1 and idx <= 8 then
      cc[idx] = msg.val
      apply_cc(idx, msg.val)
    end

  elseif msg.type == "note_on" and msg.vel > 0 then
    if msg.note == 36 then
      -- button A: reset sequences
      reset_sequences()
    elseif msg.note == 48 then
      -- button B: randomize registers
      randomize_registers()
    elseif msg.note == 60 then
      -- button C: toggle seq 1 mute
      seq[1].mute = not seq[1].mute
    elseif msg.note == 72 then
      -- button D: toggle seq 2 mute
      seq[2].mute = not seq[2].mute
    end
  end
end

function apply_cc(idx, val)
  -- faders 1-4: seq1, faders 5-8: seq2
  local n = idx <= 4 and 1 or 2
  local param = idx <= 4 and idx or (idx - 4)

  if param == 1 then
    step_count[n] = math.floor(util.linlin(0, 127, 4, 16, val) + 0.5)
    recompute_pattern(n)
  elseif param == 2 then
    pulse_count[n] = math.floor(util.linlin(0, 127, 1, step_count[n], val) + 0.5)
    recompute_pattern(n)
  elseif param == 3 then
    rotation[n] = math.floor(util.linlin(0, 127, 0, step_count[n] - 1, val) + 0.5)
    recompute_pattern(n)
  elseif param == 4 then
    flip_prob[n] = val / 127
  end
end

function reset_sequences()
  for i = 1, 2 do
    seq[i].pos = 0
  end
end

function randomize_registers()
  for i = 1, 2 do
    seq[i].register = math.random(0, 65535)
  end
end


-- sequencer

function note_off(ch, note)
  if midi_out_dev and note then
    midi_out_dev:note_off(note, 0, ch)
  end
end

function note_on(ch, note)
  if midi_out_dev then
    midi_out_dev:note_on(note, 100, ch)
  end
end

function advance(n)
  local s = seq[n]
  local pat = s.pattern
  if #pat == 0 then return end

  -- kill previous note
  if s.last_note then
    note_off(n, s.last_note)
    s.last_note = nil
  end

  s.pos = (s.pos % #pat) + 1

  if pat[s.pos] and not s.mute then
    s.register = shift_register_step(s.register, flip_prob[n])
    local sc = scales[scale_idx] or scales[1]
    local midi_note = register_to_note(s.register, sc, root, octave_range)
    -- clamp to valid midi range
    midi_note = util.clamp(midi_note, 0, 127)
    note_on(n, midi_note)
    s.last_note = midi_note
    -- push to history for display
    s.history[#s.history + 1] = midi_note
  else
    s.history[#s.history + 1] = nil
  end

  -- keep history bounded
  while #s.history > 32 do
    table.remove(s.history, 1)
  end
end

function run_sequencer()
  while true do
    clock.sync(1/4)
    advance(1)
    advance(2)
    redraw()
  end
end


-- screen: sequence view

function draw_sequences()
  -- header
  screen.level(6)
  screen.move(1, 7)
  screen.text("grurder")
  screen.move(64, 7)
  screen.text_center(note_names[root + 1] .. " " .. scale_names[scale_idx])
  screen.move(127, 7)
  screen.text_right(tempo .. "bpm o" .. octave_range)

  -- seq 1
  draw_seq_lane(seq[1], 10, 34)

  -- divider
  screen.level(2)
  screen.move(0, 36)
  screen.line(128, 36)
  screen.stroke()

  -- seq 2
  draw_seq_lane(seq[2], 38, 62)
end

function draw_seq_lane(s, y_top, y_bottom)
  local h = y_bottom - y_top
  local hist = s.history
  local count = math.min(#hist, 16)
  if count == 0 then return end

  local col_w = math.floor(128 / 16)
  local start = #hist - count + 1

  -- find pitch range in history for scaling
  local lo, hi = 127, 0
  for i = start, #hist do
    if hist[i] then
      if hist[i] < lo then lo = hist[i] end
      if hist[i] > hi then hi = hist[i] end
    end
  end
  if lo == hi then lo = lo - 6; hi = hi + 6 end

  for i = 0, count - 1 do
    local note = hist[start + i]
    local x = i * col_w
    local brightness = s.mute and 2 or (i == count - 1 and 15 or util.linlin(0, count - 1, 3, 10, i))

    if note then
      local pitch_y = util.linlin(lo, hi, y_bottom - 2, y_top + 2, note)
      screen.level(math.floor(brightness))
      screen.rect(x + 1, math.floor(pitch_y), col_w - 2, 3)
      screen.fill()
    else
      -- rest: small dot
      screen.level(s.mute and 1 or 2)
      screen.rect(x + 3, y_top + math.floor(h / 2), 2, 2)
      screen.fill()
    end
  end

  -- step indicator dots along the bottom
  if #s.pattern > 0 then
    for i = 1, #s.pattern do
      if s.pattern[i] then
        screen.level(i == s.pos and 15 or 3)
      else
        screen.level(1)
      end
      local dot_x = math.floor((i - 1) * (128 / #s.pattern))
      screen.rect(dot_x + 1, y_bottom, 2, 1)
      screen.fill()
    end
  end

  if s.mute then
    screen.level(4)
    screen.move(64, y_top + math.floor(h / 2) + 2)
    screen.text_center("MUTE")
  end
end


-- screen: fader view

function draw_faders()
  screen.level(6)
  screen.move(1, 7)
  screen.text("seq1")
  screen.move(68, 7)
  screen.text("seq2")

  local labels = {"stp", "pls", "rot", "prb", "stp", "pls", "rot", "prb"}
  local bar_w = 12
  local gap = (128 - bar_w * 8) / 9
  local base_y = 56
  local max_h = 42

  for i = 1, 8 do
    local x = math.floor(gap * i + bar_w * (i - 1))
    local h = math.floor(cc[i] / 127 * max_h)

    screen.level(12)
    screen.rect(x, base_y - h, bar_w, h)
    screen.fill()

    -- outline
    screen.level(3)
    screen.rect(x, base_y - max_h, bar_w, max_h)
    screen.stroke()

    -- label
    screen.level(6)
    screen.move(x + math.floor(bar_w / 2), 63)
    screen.text_center(labels[i])
  end
end


-- norns callbacks

function init()
  math.randomseed(os.time())

  -- params
  params:add_separator("grurder")

  params:add_number("midi_in_device", "midi in", 1, 16, 1)
  params:set_action("midi_in_device", function(val)
    midi_in_dev = midi.connect(val)
    midi_in_dev.event = handle_midi
  end)

  params:add_number("midi_out_device", "midi out", 1, 16, 2)
  params:set_action("midi_out_device", function(val)
    midi_out_dev = midi.connect(val)
  end)

  params:add_option("scale", "scale", scale_names, 1)
  params:set_action("scale", function(val)
    scale_idx = val
  end)

  -- connect midi
  midi_in_dev = midi.connect(params:get("midi_in_device"))
  midi_in_dev.event = handle_midi
  midi_out_dev = midi.connect(params:get("midi_out_device"))

  -- seed the registers
  randomize_registers()

  -- default patterns
  recompute_patterns()

  -- start sequencer
  seq_clock = clock.run(run_sequencer)

  -- redraw at 15fps
  redraw_metro = metro.init()
  redraw_metro.time = 1 / 15
  redraw_metro.event = function()
    redraw()
  end
  redraw_metro:start()
end

function key(n, z)
  if n == 2 and z == 1 then
    page = page == 1 and 2 or 1
  elseif n == 3 then
    if z == 1 then
      k3_held = util.time()
    else
      local held = util.time() - k3_held
      if held > 0.5 then
        randomize_registers()
      else
        reset_sequences()
      end
    end
  end
  redraw()
end

function enc(n, d)
  if n == 1 then
    tempo = util.clamp(tempo + d, 40, 240)
    params:set("clock_tempo", tempo)
  elseif n == 2 then
    octave_range = util.clamp(octave_range + d, 1, 4)
  elseif n == 3 then
    root = (root + d) % 12
    if root < 0 then root = root + 12 end
  end
  redraw()
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)

  if page == 1 then
    draw_sequences()
  else
    draw_faders()
  end

  screen.update()
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if seq_clock then clock.cancel(seq_clock) end

  -- all notes off
  if midi_out_dev then
    for ch = 1, 2 do
      if seq[ch].last_note then
        midi_out_dev:note_off(seq[ch].last_note, 0, ch)
      end
      midi_out_dev:cc(123, 0, ch)
    end
  end
end
