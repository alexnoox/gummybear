extends RefCounted

## Player settings, kept in Godot's user data folder (user://settings.cfg)
## so they survive a restart and a relaunch. Only control settings so far.

const PATH := "user://settings.cfg"
const SECTION := "controls"


## The saved value for `key`, or `default` if it was never saved.
static func load_value(key: String, default: Variant) -> Variant:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return default
	return file.get_value(SECTION, key, default)


static func save_value(key: String, value: Variant) -> void:
	var file := ConfigFile.new()
	# Keeps the other settings; a missing file just starts empty.
	file.load(PATH)
	file.set_value(SECTION, key, value)
	file.save(PATH)
