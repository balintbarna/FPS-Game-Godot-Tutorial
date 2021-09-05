extends Object
class_name Joypads

static func any() -> bool:
	return Input.get_connected_joypads().size() > 0


static func get_stick_index_offset_for_os() -> Array:
	# different for PS controller for some reason?
	if OS.get_name() == "Windows":
		return [0, 1]
	elif OS.get_name() == "X11":
		return [1, 2]
	elif OS.get_name() == "OSX":
		return [1, 2]
	return [-1, -1]


static func get_left_stick(xmod: int, ymod: int) -> Vector2:
	if any():
		var indices = get_stick_index_offset_for_os()
		if indices and indices.size() == 2 and not indices[0] == -1 and not indices[1] == -1:
			return Vector2(xmod * Input.get_joy_axis(0, indices[0]), ymod * Input.get_joy_axis(0, indices[1]))
	return Vector2()


static func get_right_stick(xmod: int, ymod: int) -> Vector2:
	if any():
		var indices = get_stick_index_offset_for_os()
		if indices and indices.size() == 2 and not indices[0] == -1 and not indices[1] == -1:
			return Vector2(xmod * Input.get_joy_axis(0, 2 + indices[0]), ymod * Input.get_joy_axis(0, 2 + indices[1]))
	return Vector2()


static func deadzone_correct(vec: Vector2, deadzone: float) -> Vector2:
	if vec.length() > deadzone:
		return vec.normalized() * ((vec.length() - deadzone) / (1 - deadzone))
	else:
		return Vector2()
