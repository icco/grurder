-- grurder
-- @icco
--
-- generative midi sequencer
-- euclidean rhythms + turing machine
--
-- 8mu faders control generation
-- outputs two voices to mmMidi
--
-- E1 (unused)  E2 octave  E3 root
-- K2 page   K3 reset/random (short/long)
-- 8mu faders 1-4: seq1 (steps/pulses/rot/prob)
-- 8mu faders 5-8: seq2 (steps/pulses/rot/prob)
-- 8mu tilt X/Y: velocity for seq1/seq2

local util = require "util"
local musicutil = require "musicutil"
local er = require "er"

-- scale types referencing musicutil.SCALES by name
local scale_types = {
  "Major", "Natural Minor", "Major Pentatonic", "Minor Pentatonic",
  "Dorian", "Phrygian", "Lydian", "Mixolydian"
}

-- short names for screen display
local scale_short = {
  "maj", "min", "M.pnt", "m.pnt",
  "dor", "phry", "lyd", "mixo"
}

-- state
local midi_in_dev = nil -- luacheck: no unused
local midi_out_dev = nil
local page = 1
local velocity = {100, 100}  -- derived velocity per sequence (from 8mu tilt)
local redraw_metro = nil
local seq_clock = nil
local k3_held = false

local scale_idx = 1
local root = 0
local octave_range = 2

-- per-sequence parameters (indexed 1=seq1, 2=seq2)
local step_count = {8, 8}
local pulse_count = {5, 5}
local rotation = {0, 0}
local flip_prob = {0.0, 0.0}

local seq = {
  {pattern = {}, register = 0, pos = 0, mute = false},
  {pattern = {}, register = 0, pos = 0, mute = false},
}


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

function register_to_note(reg, root_note, oct_range)
  local scale_notes = musicutil.generate_scale(root_note + 36, scale_types[scale_idx], oct_range)
  local idx = (reg % #scale_notes) + 1
  return scale_notes[idx]
end


-- pattern computation

function recompute_pattern(n)
  seq[n].pattern = er.gen(pulse_count[n], step_count[n], rotation[n])
end

function recompute_patterns()
  recompute_pattern(1)
  recompute_pattern(2)
end


-- midi input handler

function handle_midi(data)
  local msg = midi.to_msg(data)

  if msg.type == "cc" then
    -- 8mu accelerometer tilt: CC 14 = X (seq1 vel), CC 15 = Y (seq2 vel)
    if msg.cc == 14 then
      velocity[1] = math.floor(util.linlin(0, 127, 30, 127, msg.val))
    elseif msg.cc == 15 then
      velocity[2] = math.floor(util.linlin(0, 127, 30, 127, msg.val))
    end

    local idx = msg.cc - 33
    if idx >= 1 and idx <= 8 then
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
    pulse_count[n] = math.min(pulse_count[n], step_count[n])
    rotation[n] = math.min(rotation[n], step_count[n] - 1)
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

function note_on(ch, note, vel)
  if midi_out_dev then
    midi_out_dev:note_on(note, vel or 100, ch)
  end
end

function advance(n)
  local s = seq[n]
  local pat = s.pattern
  if #pat == 0 then return end

  s.pos = (s.pos % #pat) + 1

  if pat[s.pos] and not s.mute then
    s.register = shift_register_step(s.register, flip_prob[n])
    local midi_note = util.clamp(register_to_note(s.register, root, octave_range), 0, 127)
    local vel = velocity[n]
    note_on(n, midi_note, vel)
    local gate_sec = clock.get_beat_sec() * 0.25 * 0.5
    clock.run(function()
      clock.sleep(gate_sec)
      note_off(n, midi_note)
    end)
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

function draw_seq_blocks(n, y)
  local s = seq[n]
  local pat = s.pattern
  local steps = #pat
  if steps == 0 then return end

  local x_off = 12
  local block_w = math.floor((128 - x_off) / steps)
  local block_h = 11

  screen.level(s.mute and 2 or 5)
  screen.move(1, y + 8)
  screen.text(n .. ":")

  for i = 1, steps do
    local x = x_off + (i - 1) * block_w
    if i == s.pos then
      screen.level(15)
      screen.rect(x, y, block_w - 1, block_h)
      screen.fill()
    elseif pat[i] then
      screen.level(s.mute and 2 or 5)
      screen.rect(x, y, block_w - 1, block_h)
      screen.fill()
    else
      screen.level(s.mute and 1 or 2)
      screen.rect(x, y, block_w - 1, block_h)
      screen.stroke()
    end
  end

  if s.mute then
    screen.level(10)
    screen.move(64, y + 8)
    screen.text_center("mute")
  end
end

function draw_sequences()
  screen.level(6)
  screen.move(1, 7)
  screen.text(musicutil.note_num_to_name(root, false) .. " " .. scale_short[scale_idx])
  screen.move(64, 7)
  screen.text_center(math.floor(clock.get_tempo()) .. " bpm")
  screen.move(127, 7)
  screen.text_right("o" .. octave_range)

  draw_seq_blocks(1, 10)

  screen.level(2)
  screen.move(0, 27)
  screen.line(128, 27)
  screen.stroke()

  draw_seq_blocks(2, 30)

  screen.level(3)
  screen.move(1, 62)
  screen.text("s" .. step_count[1] .. " p" .. pulse_count[1] .. " r" .. rotation[1] .. " v" .. velocity[1])
  screen.move(127, 62)
  screen.text_right("s" .. step_count[2] .. " p" .. pulse_count[2] .. " r" .. rotation[2] .. " v" .. velocity[2])
end


-- screen: params view

function draw_params()
  local function row(label, v1, v2, y)
    screen.level(4)
    screen.move(1, y)
    screen.text(label)
    screen.level(10)
    screen.move(80, y)
    screen.text_center(v1)
    screen.move(127, y)
    screen.text_right(v2)
  end

  screen.level(6)
  screen.move(1, 7)
  screen.text("params")
  screen.move(80, 7)
  screen.text_center("seq1")
  screen.move(127, 7)
  screen.text_right("seq2")

  row("steps",  step_count[1],  step_count[2],  18)
  row("pulses", pulse_count[1], pulse_count[2], 28)
  row("rotate", rotation[1],    rotation[2],    38)
  row("prob",   math.floor(flip_prob[1] * 100) .. "%", math.floor(flip_prob[2] * 100) .. "%", 48)
  row("vel",    velocity[1],    velocity[2],    58)
end


-- norns callbacks

function midi_device_names()
  local names = {}
  for i = 1, #midi.vports do
    local name = midi.vports[i].name or ("port " .. i)
    names[i] = i .. ": " .. name
  end
  return names
end

function init()
  math.randomseed(os.time())

  -- params
  params:add_separator("grurder")

  params:add_option("midi_in_device", "midi in", midi_device_names(), 1)
  params:set_action("midi_in_device", function(val)
    midi_in_dev = midi.connect(val)
    midi_in_dev.event = handle_midi
  end)

  params:add_option("midi_out_device", "midi out", midi_device_names(), 2)
  params:set_action("midi_out_device", function(val)
    midi_out_dev = midi.connect(val)
  end)

  params:add_option("scale", "scale", scale_types, 1)
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
  if n == 2 then
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
    draw_params()
  end

  screen.update()
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if seq_clock then clock.cancel(seq_clock) end

  -- all notes off
  if midi_out_dev then
    for ch = 1, 2 do
      midi_out_dev:cc(123, 0, ch)
    end
  end
end
