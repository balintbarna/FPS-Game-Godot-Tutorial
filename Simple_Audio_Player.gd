extends Spatial

# All of the audio files.
# You will need to provide your own sound files.
var sounds = {
	"Pistol_shot": preload("res://assets/Sounds/gun_revolver_pistol_shot_04.wav"),
	"Rifle_shot": preload("res://assets/Sounds/gun_rifle_sniper_shot_01.wav"),
	"Gun_cock": preload("res://assets/Sounds/gun_semi_auto_rifle_cock_02.wav")
}

func _ready():
	$Player.connect("finished", self, "destroy_self")
	$Player3D.connect("finished", self, "destroy_self")
	$Player.stop()
	$Player3D.stop()


func play_sound(sound_name, position = null):
	var audio_node = $Player
	if position != null:
		audio_node = $Player3D
		audio_node.global_transform.origin = position
	   
	var sound = sounds[sound_name]
	if sound == null:
		print("UNKNOWN SOUND NAME:" + sound_name)
		queue_free()
		return
	else:
		audio_node.stream = sound

	audio_node.play()


func destroy_self():
	$Player.stop()
	$Player3D.stop()
	queue_free()
