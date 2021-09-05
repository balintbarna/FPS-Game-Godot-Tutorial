extends KinematicBody

const up = Vector3(0, 1, 0)
export var NORMAL_ACCELERATION_PER_SECOND = 200
export var SPRINT_ACCELERATION_PER_SECOND = 400
export var NORMAL_MAX_SPEED_PER_SECOND = 20
export var SPRINT_MAX_SPEED_PER_SECOND = 40
export var MIN_DAMPEN_PER_SECOND = 40
export var DAMPEN_RATIO_PER_SECOND = 3
export var JUMP_SPEED = 50
export var GRAVITY_PER_SECOND = 100
export var AIR_DAMPEN_MULT = 0.3
export var MOUSE_SENSITIVITY = 0.5
export var JOYPAD_SENSITIVITY = 2
export var JOYPAD_DEADZONE = 0.15
export var MOUSE_SENSITIVITY_SCROLL_WHEEL = 0.08
export var MAX_HEALTH = 150


var acceleration_per_second = NORMAL_ACCELERATION_PER_SECOND
var max_speed_per_second = NORMAL_MAX_SPEED_PER_SECOND
var velocity = Vector3()
var health = 100
var simple_audio_player = preload("res://Simple_Audio_Player.tscn")


onready var rotation_helper = $Rotation_Helper
onready var mouse_hint = $HUD/MouseHint
onready var flashlight = $Rotation_Helper/Flashlight
onready var animation_manager = $Rotation_Helper/Model/Animation_Player
onready var ui_status_label = $HUD/Panel/Gun_label
onready var camera = $Rotation_Helper/Camera


const KEY_UNARMED = "UNARMED"
const KEY_KNIFE = "KNIFE"
const KEY_PISTOL = "PISTOL"
const KEY_RIFLE = "RIFLE"
var current_weapon_name = KEY_UNARMED
var weapons = {KEY_UNARMED:null, KEY_KNIFE:null, KEY_PISTOL:null, KEY_RIFLE:null}
const WEAPON_NUMBER_TO_NAME = {0:KEY_UNARMED, 1:KEY_KNIFE, 2:KEY_PISTOL, 3:KEY_RIFLE}
const WEAPON_NAME_TO_NUMBER = {KEY_UNARMED:0, KEY_KNIFE:1, KEY_PISTOL:2, KEY_RIFLE:3}
var changing_weapon = false
var changing_weapon_name = KEY_UNARMED
var reloading_weapon = false
var mouse_scroll_value = 0


const KEY_GRENADE = "Grenade"
const KEY_STICKY_GRENADE = "Sticky Grenade"
var grenade_amounts = {KEY_GRENADE:2, KEY_STICKY_GRENADE:2}
var current_grenade = KEY_GRENADE
var grenade_scene = preload("res://Grenade.tscn")
var sticky_grenade_scene = preload("res://Sticky_Grenade.tscn")
const GRENADE_THROW_FORCE = 50


var grabbed_object = null
const OBJECT_THROW_FORCE = 120
const OBJECT_GRAB_DISTANCE = 7
const OBJECT_GRAB_RAY_DISTANCE = 10


const RESPAWN_TIME = 1
var dead_time = 0
var is_dead = false


# Called when the node enters the scene tree for the first time.
func _ready():
	global_transform.origin = Globals.get_respawn_position()
	animation_manager.callback_function = funcref(self, "fire_bullet")

	weapons[KEY_KNIFE] = $Rotation_Helper/Gun_Fire_Points/Knife_Point
	weapons[KEY_PISTOL] = $Rotation_Helper/Gun_Fire_Points/Pistol_Point
	weapons[KEY_RIFLE] = $Rotation_Helper/Gun_Fire_Points/Rifle_Point

	var gun_aim_point_pos = $Rotation_Helper/Gun_Aim_Point.global_transform.origin
	for weapon in weapons:
		var weapon_node = weapons[weapon]
		if weapon_node != null:
			weapon_node.player_node = self
			weapon_node.look_at(gun_aim_point_pos, Vector3(0, 1, 0))
			weapon_node.rotate_object_local(Vector3(0, 1, 0), deg2rad(180))


func _physics_process(delta):
	if not is_dead:
		process_flashlight()
		process_mouse_capture()
		process_joypad_orientation()
		process_movement(delta)
		process_weapons()
		process_grenade()
		process_grab_throw()

	process_UI(delta)
	process_respawn(delta)


func _input(event):
	if is_dead:
		return

	if is_captured():
		if event is InputEventMouseMotion:
			mouse_motion_character_rotation(event)
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_WHEEL_UP or event.button_index == BUTTON_WHEEL_DOWN:
				if event.button_index == BUTTON_WHEEL_UP:
					mouse_scroll_value += MOUSE_SENSITIVITY_SCROLL_WHEEL
				elif event.button_index == BUTTON_WHEEL_DOWN:
					mouse_scroll_value -= MOUSE_SENSITIVITY_SCROLL_WHEEL
		
				mouse_scroll_value = clamp(mouse_scroll_value, 0, WEAPON_NUMBER_TO_NAME.size() - 1)
		
				if changing_weapon == false:
					if reloading_weapon == false:
						var round_mouse_scroll_value = int(round(mouse_scroll_value))
						if WEAPON_NUMBER_TO_NAME[round_mouse_scroll_value] != current_weapon_name:
							changing_weapon_name = WEAPON_NUMBER_TO_NAME[round_mouse_scroll_value]
							changing_weapon = true
							mouse_scroll_value = round_mouse_scroll_value


func process_joypad_orientation():
	if Joypads.any():
		var joypad_vec = Joypads.get_right_stick(1, 1)
		if joypad_vec.length() > JOYPAD_DEADZONE:
			joypad_vec = joypad_vec.normalized() * ((joypad_vec.length() - JOYPAD_DEADZONE) / (1 - JOYPAD_DEADZONE))
		else:
			return

		rotation_helper.rotate_x(deg2rad(joypad_vec.y * JOYPAD_SENSITIVITY))

		rotate_y(deg2rad(joypad_vec.x * JOYPAD_SENSITIVITY * -1))

		var camera_rot = rotation_helper.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, -70, 70)
		rotation_helper.rotation_degrees = camera_rot
	


func process_movement(delta):
	handle_sprint()
	apply_dampening(delta)
	# apply gravity
	velocity.y -= GRAVITY_PER_SECOND * delta
	accelerate_from_inputs(delta)
	limit_horizontal_speed()
	# apply velocity
	velocity = move_and_slide(velocity, up)


func process_mouse_capture():
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_hint.hide()


func is_captured():
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func apply_dampening(delta):
	var min_dampen = MIN_DAMPEN_PER_SECOND * delta
	if velocity.length() < min_dampen:
		velocity = Vector3(0, velocity.y, 0)
	else:
		var dampen_ratio = DAMPEN_RATIO_PER_SECOND * delta
		var dampen = dampen_ratio * velocity
		if dampen.length() < min_dampen:
			dampen = dampen.normalized() * min_dampen
		if not is_on_floor():
			dampen *= AIR_DAMPEN_MULT
		velocity -= dampen


func accelerate_from_inputs(delta):
	if is_on_floor():
		var acceleration = acceleration_per_second * delta
		var horizontal_velocity_change = (get_action_input_movement_vector() + get_joypad_movement_vector()) * acceleration
		if Input.is_action_pressed("movement_jump"):
			velocity.y = JUMP_SPEED
		horizontal_velocity_change = horizontal_velocity_change.rotated(-self.rotation.y)
		velocity.x += horizontal_velocity_change.x
		velocity.z += horizontal_velocity_change.y


func get_action_input_movement_vector() -> Vector2:
	var vec = Vector2()
	if Input.is_action_pressed("movement_forward"):
		vec.y += 1
	if Input.is_action_pressed("movement_backward"):
		vec.y -= 1
	if Input.is_action_pressed("movement_left"):
		vec.x += 1
	if Input.is_action_pressed("movement_right"):
		vec.x -= 1
	return vec


func get_joypad_movement_vector() -> Vector2:
	return Joypads.deadzone_correct(Joypads.get_left_stick(-1, -1), JOYPAD_DEADZONE)


func limit_horizontal_speed():
	var vertical = velocity.y
	velocity.y = 0
	if velocity.length() > max_speed_per_second:
		velocity = velocity.normalized() * max_speed_per_second
	velocity.y = vertical


func handle_sprint():
	if Input.is_action_pressed("movement_sprint"):
		max_speed_per_second = SPRINT_MAX_SPEED_PER_SECOND
		acceleration_per_second = SPRINT_ACCELERATION_PER_SECOND
	else:
		max_speed_per_second = NORMAL_MAX_SPEED_PER_SECOND
		acceleration_per_second = NORMAL_ACCELERATION_PER_SECOND


func process_flashlight():
	if Input.is_action_just_pressed("flashlight"):
		# flashlight.visible = !flashlight.visible
		if flashlight.is_visible_in_tree():
			flashlight.hide()
		else:
			flashlight.show()


func mouse_motion_character_rotation(event: InputEventMouseMotion):
	rotation_helper.rotate_x(deg2rad(event.relative.y * MOUSE_SENSITIVITY))
	self.rotate_y(deg2rad(event.relative.x * MOUSE_SENSITIVITY * -1))

	var camera_rot = rotation_helper.rotation_degrees
	camera_rot.x = clamp(camera_rot.x, -70, 70)
	rotation_helper.rotation_degrees = camera_rot


func process_weapons():
	if grabbed_object != null:
		return
	process_weapon_change_input()
	process_changing_weapons()
	process_reload_input()
	process_reloading()
	process_weapon_fire_input()


func process_weapon_change_input():
	var weapon_change_number = WEAPON_NAME_TO_NUMBER[current_weapon_name]
	if Input.is_key_pressed(KEY_1):
		weapon_change_number = 0
	if Input.is_key_pressed(KEY_2):
		weapon_change_number = 1
	if Input.is_key_pressed(KEY_3):
		weapon_change_number = 2
	if Input.is_key_pressed(KEY_4):
		weapon_change_number = 3

	if Input.is_action_just_pressed("shift_weapon_positive"):
		weapon_change_number += 1
	if Input.is_action_just_pressed("shift_weapon_negative"):
		weapon_change_number -= 1

	weapon_change_number = clamp(weapon_change_number, 0, WEAPON_NUMBER_TO_NAME.size() - 1)

	if not changing_weapon and not reloading_weapon:
		if WEAPON_NUMBER_TO_NAME[weapon_change_number] != current_weapon_name:
			changing_weapon_name = WEAPON_NUMBER_TO_NAME[weapon_change_number]
			changing_weapon = true
			mouse_scroll_value = weapon_change_number


func process_weapon_fire_input():
	if Input.is_action_pressed("fire"):
		if not changing_weapon and not reloading_weapon:
			var current_weapon = weapons[current_weapon_name]
			if current_weapon and current_weapon.ammo_in_weapon > 0:
				if animation_manager.current_state == current_weapon.IDLE_ANIM_NAME:
					animation_manager.set_animation(current_weapon.FIRE_ANIM_NAME)
			else:
				reloading_weapon = true


func process_reload_input():
	if not changing_weapon and not reloading_weapon:
		if Input.is_action_just_pressed("reload"):
			var current_weapon = weapons[current_weapon_name]
			if current_weapon != null:
				if current_weapon.CAN_RELOAD == true:
					var current_anim_state = animation_manager.current_state
					var is_reloading = false
					for weapon in weapons:
						var weapon_node = weapons[weapon]
						if weapon_node != null:
							if current_anim_state == weapon_node.RELOADING_ANIM_NAME:
								is_reloading = true
					if is_reloading == false:
						reloading_weapon = true


func process_changing_weapons():
	if changing_weapon == true:
		var current_weapon = weapons[current_weapon_name]
		var weapon_unequipped = current_weapon == null
		if not weapon_unequipped:
			if current_weapon.is_weapon_enabled == true:
				weapon_unequipped = current_weapon.unequip_weapon()
			else:
				weapon_unequipped = true

		if weapon_unequipped:

			var weapon_equipped = false
			var weapon_to_equip = weapons[changing_weapon_name]

			if weapon_to_equip == null:
				weapon_equipped = true
			else:
				if weapon_to_equip.is_weapon_enabled == false:
					weapon_equipped = weapon_to_equip.equip_weapon()
				else:
					weapon_equipped = true

			if weapon_equipped == true:
				changing_weapon = false
				current_weapon_name = changing_weapon_name
				changing_weapon_name = ""


func fire_bullet():
	if changing_weapon or reloading_weapon:
		return
	var weapon = weapons[current_weapon_name]
	weapon.fire_weapon()


func process_grenade():
	process_change_grenade()
	process_throw_grenade()


func process_change_grenade():
	if Input.is_action_just_pressed("change_grenade"):
		if current_grenade == KEY_GRENADE:
			current_grenade = KEY_STICKY_GRENADE
		elif current_grenade == KEY_STICKY_GRENADE:
			current_grenade = KEY_GRENADE


func process_throw_grenade():
	if Input.is_action_just_pressed("fire_grenade") and current_weapon_name != KEY_UNARMED:
		if grenade_amounts[current_grenade] > 0:
			grenade_amounts[current_grenade] -= 1
	
			var grenade_clone
			if current_grenade == KEY_GRENADE:
				grenade_clone = grenade_scene.instance()
			elif current_grenade == KEY_STICKY_GRENADE:
				grenade_clone = sticky_grenade_scene.instance()
				# Sticky grenades will stick to the player if we do not pass ourselves
				grenade_clone.player_body = self
	
			get_tree().root.add_child(grenade_clone)
			grenade_clone.global_transform = $Rotation_Helper/Grenade_Toss_Pos.global_transform
			grenade_clone.apply_impulse(Vector3(0, 0, 0), grenade_clone.global_transform.basis.z * GRENADE_THROW_FORCE)


func process_grab_throw():
	if Input.is_action_just_pressed("fire_grenade") and current_weapon_name == KEY_UNARMED:
		if grabbed_object == null:
			var state = get_world().direct_space_state
	
			var center_position = get_viewport().size / 2
			var ray_from = camera.project_ray_origin(center_position)
			var ray_to = ray_from + camera.project_ray_normal(center_position) * OBJECT_GRAB_RAY_DISTANCE
	
			var ray_result = state.intersect_ray(ray_from, ray_to, [self, $Rotation_Helper/Gun_Fire_Points/Knife_Point/Area])
			if !ray_result.empty():
				if ray_result["collider"] is RigidBody:
					grabbed_object = ray_result["collider"]
					grabbed_object.mode = RigidBody.MODE_STATIC
	
					grabbed_object.collision_layer = 0
					grabbed_object.collision_mask = 0
	
		else:
			grabbed_object.mode = RigidBody.MODE_RIGID
	
			grabbed_object.apply_impulse(Vector3(0, 0, 0), -camera.global_transform.basis.z.normalized() * OBJECT_THROW_FORCE)
	
			grabbed_object.collision_layer = 1
			grabbed_object.collision_mask = 1
	
			grabbed_object = null
	
	if grabbed_object != null:
		grabbed_object.global_transform.origin = camera.global_transform.origin + (-camera.global_transform.basis.z.normalized() * OBJECT_GRAB_DISTANCE)


func add_health(additional_health):
	health += additional_health
	health = clamp(health, 0, MAX_HEALTH)


func add_ammo(additional_ammo):
	if (current_weapon_name != "UNARMED"):
		if (weapons[current_weapon_name].CAN_REFILL == true):
			weapons[current_weapon_name].spare_ammo += weapons[current_weapon_name].AMMO_IN_MAG * additional_ammo


func add_grenade(additional_grenade):
	grenade_amounts[current_grenade] += additional_grenade
	grenade_amounts[current_grenade] = clamp(grenade_amounts[current_grenade], 0, 4)


func process_UI(_delta):
	if changing_weapon or current_weapon_name == "UNARMED" or current_weapon_name == "KNIFE":
		ui_status_label.text = "HEALTH: " + str(health) + \
		"\n" + current_grenade + ": " + str(grenade_amounts[current_grenade])
	else:
		var current_weapon = weapons[current_weapon_name]
		ui_status_label.text = "HEALTH: " + str(health) + \
				"\nAMMO: " + str(current_weapon.ammo_in_weapon) + "/" + str(current_weapon.spare_ammo) + \
				"\n" + current_grenade + ": " + str(grenade_amounts[current_grenade])

func process_reloading():
	if reloading_weapon == true:
		var current_weapon = weapons[current_weapon_name]
		if current_weapon != null:
			current_weapon.reload_weapon()
		reloading_weapon = false


func process_respawn(delta):

	# If we've just died
	if health <= 0 and !is_dead:
		$Body_CollisionShape.disabled = true
		$Feet_CollisionShape.disabled = true

		changing_weapon = true
		changing_weapon_name = "UNARMED"

		$HUD/Death_Screen.visible = true

		$HUD/Panel.visible = false
		$HUD/Crosshair.visible = false

		dead_time = RESPAWN_TIME
		is_dead = true

		if grabbed_object != null:
			grabbed_object.mode = RigidBody.MODE_RIGID
			grabbed_object.apply_impulse(Vector3(0, 0, 0), -camera.global_transform.basis.z.normalized() * OBJECT_THROW_FORCE / 2)

			grabbed_object.collision_layer = 1
			grabbed_object.collision_mask = 1

			grabbed_object = null

	if is_dead:
		dead_time -= delta

		var dead_time_pretty = str(dead_time).left(3)
		$HUD/Death_Screen/Label.text = "You died\n" + dead_time_pretty + " seconds till respawn"

		if dead_time <= 0:
			global_transform.origin = Globals.get_respawn_position()

			$Body_CollisionShape.disabled = false
			$Feet_CollisionShape.disabled = false

			$HUD/Death_Screen.visible = false

			$HUD/Panel.visible = true
			$HUD/Crosshair.visible = true

			for weapon in weapons:
				var weapon_node = weapons[weapon]
				if weapon_node != null:
					weapon_node.reset_weapon()

			health = 100
			grenade_amounts = {"Grenade":2, "Sticky Grenade":2}
			current_grenade = "Grenade"

			is_dead = false


func create_sound(sound_name, position=null):
	var audio_clone = simple_audio_player.instance()
	var scene_root = get_tree().root.get_children()[0]
	scene_root.add_child(audio_clone)
	audio_clone.play_sound(sound_name, position)


func bullet_hit(damage, bullet_hit_pos):
	health -= damage
