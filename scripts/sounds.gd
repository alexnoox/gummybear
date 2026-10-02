extends Node

## Sound effects the players record themselves (pause menu → Sounds). Each
## game moment in EVENTS plays its recording, if it has one, at a slightly
## random pitch so repeats don't sound robotic. An autoload: anything can
## call `Sounds.play("throw")`.
##
## Two layers of WAV files, <event>.wav, the first found wins:
## 1. This computer's own recordings, in `directory`.
## 2. The project's PROJECT_DIR (res://sounds, tracked in git), which every
##    build ships, so the Windows PC by the TV gets the Mac's recordings.
## Run from the project source (the Mac), `directory` *is* PROJECT_DIR:
## recordings land in the repo and go out on the next push. In an exported
## build (the PC) it's user://sounds: the PC's own recordings win there,
## and clearing one falls back to the shipped one.
##
## Recording uses Godot's microphone path: an AudioStreamMicrophone playing
## into a muted "Record" bus whose AudioEffectRecord captures it (needs
## audio/driver/enable_input; macOS asks for microphone permission the first
## time). A recording stops on `stop_recording()` or after MAX_SECONDS.

## Emitted when a recording ends; `ok` is false if nothing came in (no
## microphone, or permission denied).
signal recorded(event: String, ok: bool)

const EVENTS := ["throw", "hit", "pop", "win", "walk"]
const MAX_SECONDS := 3.0
## Shorter than this is treated as nothing recorded.
const MIN_SECONDS := 0.1
const PITCH_JITTER := 0.1
## Events that never overlap themselves (footsteps would pile up).
const NO_OVERLAP := ["walk"]
const VOICES := 8
## Trimming: a recording starts when Record is pressed, so it opens with the
## silence before the voice (and ends with the pause before letting go),
## which would play as a delay. Loudness is measured in TRIM_WINDOW (s)
## slices; sound is any slice within TRIM_THRESHOLD of the loudest and above
## TRIM_FLOOR (RMS, 16-bit), so hiss doesn't count. PRE_ROLL and POST_ROLL
## (s) are kept around it, with FADE (s) ramps so the cut doesn't click.
const TRIM_WINDOW := 0.01
const TRIM_THRESHOLD := 0.1
const TRIM_FLOOR := 300.0
const PRE_ROLL := 0.03
const POST_ROLL := 0.1
const FADE := 0.01
const RECORD_BUS := "Record"

## Recordings shipped with the game (imported by Godot, so a build carries
## them).
const PROJECT_DIR := "res://sounds"
const USER_DIR := "user://sounds"

## Where this computer's recordings are written and read first.
var directory := PROJECT_DIR if OS.has_feature("editor") else USER_DIR

var _streams := {}
var _plays := {}
var _voices: Array[AudioStreamPlayer] = []
var _mic: AudioStreamPlayer
var _recorder: AudioEffectRecord
var _recording_event := ""
var _recording_left := 0.0


func _ready() -> void:
	# Plays and records in the (paused) pause menu too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	var bus := AudioServer.get_bus_index(RECORD_BUS)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, RECORD_BUS)
		AudioServer.add_bus_effect(bus, AudioEffectRecord.new())
	# Muted so the microphone isn't played back out of the speakers; the
	# effect still records.
	AudioServer.set_bus_mute(bus, true)
	_recorder = AudioServer.get_bus_effect(bus, 0)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = RECORD_BUS
	add_child(_mic)
	load_all()


## Switches the folder recordings live in and reloads them (the --shots
## harness uses its own folder).
func use_directory(path: String) -> void:
	directory = path
	load_all()


func load_all() -> void:
	_streams.clear()
	for event: String in EVENTS:
		_load_event(event)


func _load_event(event: String) -> void:
	_streams.erase(event)
	var wav := _load_wav(_path(event))
	if wav == null:
		wav = _load_wav("%s/%s.wav" % [PROJECT_DIR, event])
	if wav != null:
		_streams[event] = wav


## The WAV at `path`: read straight from the file when it's there (user://,
## or res:// run from source, which may be newer than Godot's import of it),
## else Godot's imported copy (res:// in an exported build).
func _load_wav(path: String) -> AudioStreamWAV:
	if FileAccess.file_exists(path):
		return AudioStreamWAV.load_from_file(path)
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as AudioStreamWAV
	return null


func has_sound(event: String) -> bool:
	return _streams.has(event)


## True if this computer recorded `event` itself (so Clear has something to
## clear); false for a sound that only ships with the game.
func has_own_sound(event: String) -> bool:
	return FileAccess.file_exists(_path(event))


## The events that have a recording shipped with the game.
func shipped_events() -> Array:
	return EVENTS.filter(func(event: String) -> bool:
		return _load_wav("%s/%s.wav" % [PROJECT_DIR, event]) != null)


## True when recordings go into the project (run from source on the Mac).
func records_into_project() -> bool:
	return directory == PROJECT_DIR


## Plays `event`'s recording, if any; `jitter` varies the pitch a little.
func play(event: String, jitter := true) -> void:
	if not _streams.has(event):
		return
	if event in NO_OVERLAP and _is_playing(event):
		return
	_plays[event] = _plays.get(event, 0) + 1
	var voice := _free_voice()
	voice.stream = _streams[event]
	voice.pitch_scale = (randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
			if jitter else 1.0)
	voice.set_meta("event", event)
	voice.play()


## How many times `event` has played (for the --shots harness).
func play_count(event: String) -> int:
	return _plays.get(event, 0)


## Stores `wav` as `event`'s sound and saves it. Returns false if the file
## couldn't be written (the sound still plays this session).
func set_sound(event: String, wav: AudioStreamWAV) -> bool:
	_streams[event] = wav
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	return wav.save_to_wav(_path(event)) == OK


## Deletes this computer's recording of `event`; a shipped one (if any)
## takes over again.
func clear(event: String) -> void:
	var path := _path(event)
	for file in [path, path + ".import"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	_load_event(event)


func is_recording() -> bool:
	return not _recording_event.is_empty()


func start_recording(event: String) -> void:
	if is_recording():
		return
	_recording_event = event
	_recording_left = MAX_SECONDS
	_mic.play()
	_recorder.set_recording_active(true)


## Ends the recording in progress (no-op if none) and keeps it if anything
## came in; emits `recorded`.
func stop_recording() -> void:
	if not is_recording():
		return
	# Too short to keep: skip get_recording(), which errors when nothing
	# has been captured yet.
	var wav: AudioStreamWAV = (_recorder.get_recording()
			if MAX_SECONDS - _recording_left >= MIN_SECONDS else null)
	_recorder.set_recording_active(false)
	_mic.stop()
	var event := _recording_event
	_recording_event = ""
	if wav != null:
		wav = trim_silence(wav)
	var ok := wav != null and _seconds(wav) >= MIN_SECONDS
	if ok:
		set_sound(event, wav)
	recorded.emit(event, ok)


func _process(delta: float) -> void:
	if is_recording():
		_recording_left -= delta
		if _recording_left <= 0.0:
			stop_recording()


## `wav` without the silence before and after the sound (16-bit only; other
## formats, or a recording with no sound in it, come back unchanged).
static func trim_silence(wav: AudioStreamWAV) -> AudioStreamWAV:
	if wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return wav
	var channels := 2 if wav.stereo else 1
	var frame_bytes := 2 * channels
	var data := wav.data
	var frames := data.size() / frame_bytes
	var window := maxi(1, int(wav.mix_rate * TRIM_WINDOW))
	var levels := PackedFloat32Array()
	for start in range(0, frames, window):
		var energy := 0.0
		var end := mini(start + window, frames)
		for i in range(start * channels, end * channels):
			var sample := float(data.decode_s16(i * 2))
			energy += sample * sample
		levels.append(sqrt(energy / ((end - start) * channels)))
	var loudest := 0.0
	for level in levels:
		loudest = maxf(loudest, level)
	var threshold := maxf(loudest * TRIM_THRESHOLD, TRIM_FLOOR)
	var first := -1
	var last := -1
	for i in levels.size():
		if levels[i] >= threshold:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return wav
	var from := maxi(0, first * window - int(PRE_ROLL * wav.mix_rate))
	var to := mini(frames, (last + 1) * window + int(POST_ROLL * wav.mix_rate))
	var kept := data.slice(from * frame_bytes, to * frame_bytes)
	var count := to - from
	var fade := mini(int(FADE * wav.mix_rate), count / 2)
	for f in fade:
		var gain := float(f) / fade
		for c in channels:
			for at in [(f * channels + c) * 2, ((count - 1 - f) * channels + c) * 2]:
				kept.encode_s16(at, int(kept.decode_s16(at) * gain))
	var trimmed: AudioStreamWAV = wav.duplicate()
	trimmed.data = kept
	return trimmed


func _path(event: String) -> String:
	return "%s/%s.wav" % [directory, event]


func _seconds(wav: AudioStreamWAV) -> float:
	var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) \
			* (2 if wav.stereo else 1)
	return float(wav.data.size()) / (bytes_per_frame * wav.mix_rate)


func _is_playing(event: String) -> bool:
	for voice in _voices:
		if voice.playing and voice.get_meta("event", "") == event:
			return true
	return false


## A voice that's free, or else the first one (cut short).
func _free_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	return _voices[0]
