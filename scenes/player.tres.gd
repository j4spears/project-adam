extends CharacterBody2D

#region VARIABLES

@export_category("Move")
@export var speed: float = 500
@export var acceleration:= 5
@export var deceleration:= 5
@export var dodge_speed:= 1000
enum variable_speed_type {none, discrete, continuous}
@export var variable_speed = variable_speed_type.none

@export_category("Jump")
@export var jump_force:= 400
@export var airborne_acceleration:= 3
@export var airborne_deceleration:= 3
@export var hang_time:= false
enum variable_jump_type {none, smooth, sharp}
@export var variable_jump = variable_jump_type.none
@export var max_fall_speed:= 200
@export_subgroup("gravity")
@export var ascend:= 20
@export var descend:= 50

@export_category("Wall Slide")
@export var wallslide_speed = 300
@export var wall_jump_distance = 300

@export_category("Gun")
@export var bullet_speed: float = 4000
@export var bullet_knockback: = 50
@export var dash_speed: float = 2000
@export var dash_length: float = 0.1
enum aiming_type {discrete, continuous}
@export var aiming = aiming_type.discrete

@export_category("Abilities")
@export var has_dash: bool = true
@export var has_burst: bool = true
@export var has_wallslide: bool = true
@export var has_aiming_schematic: bool = true

@onready var hang_timer: Timer = $Timers/HangTime
@onready var jump_buffer: Timer = $Timers/JumpBuffer
@onready var cayote_time: Timer = $Timers/CayoteTime
@onready var dash_time: Timer = $Timers/DashTime
@onready var shoot_cooldown: Timer = $Timers/ShootCooldown
@onready var burst_cooldown: Timer = $Timers/BurstCooldown
@onready var dodge_time: Timer = $Timers/DodgeTime

@onready var blast_sfx: AudioStreamPlayer = $Sfx/Blast
@onready var jump_sfx: AudioStreamPlayer = $Sfx/Jump
@onready var bullet_sfx: AudioStreamPlayer = $Sfx/Bullet
@onready var burst_bullet_sfx: AudioStreamPlayer = $Sfx/BurstBullet

@onready var gun: Sprite2D = $Gun
@onready var body: Sprite2D = $Body
@onready var blast_area: Area2D = $Gun/BlastArea
@onready var blast_collision: CollisionPolygon2D = $Gun/BlastArea/BlastCollision
@onready var label: Label = $Label


const blast_vfx = preload("res://scenes/blast_vfx.tscn")
const bullet = preload("res://scenes/bullet.tscn")
const burst_bullet = preload("res://scenes/burst_bullet.tscn")

var rs_zone
var ls_zone
var dash_used:= false
var burst_used:= false
var burst_in_use := false
var bullets_shot := 0

#endregion

#region STATE MACHINE

enum states {RUN, JUMP, FALL, DASH, CROUCH, WALLSLIDE, DODGEROLL}
var state =  states.FALL
var previous_state = states.JUMP
var msg = []

func change_state(new_state):
	
	match state:
		states.RUN: 
			previous_state = states.RUN
			exit_run()
		states.JUMP: 
			previous_state = states.JUMP
			exit_jump()
		states.FALL: 
			previous_state = states.FALL
			exit_fall()
		states.DASH: 
			previous_state = states.DASH
			exit_dash()
		states.CROUCH: 
			previous_state = states.CROUCH
			exit_crouch()
		states.WALLSLIDE: 
			previous_state = states.WALLSLIDE
			exit_wallslide()
		states.DODGEROLL: 
			previous_state = states.DODGEROLL
			exit_dodgeroll()
	
	state = new_state
	
	match state:
		states.RUN: enter_run()
		states.JUMP: enter_jump()
		states.FALL: enter_fall()
		states.DASH: enter_dash()
		states.CROUCH: enter_crouch()
		states.WALLSLIDE: enter_wallslide()
		states.DODGEROLL: enter_dodgeroll()

func _physics_process(delta):
	
	match state:
		states.RUN: run(delta)
		states.JUMP: jump(delta)
		states.FALL: fall(delta)
		states.DASH: dash(delta)
		states.CROUCH: crouch(delta)
		states.WALLSLIDE: wallslide(delta)
		states.DODGEROLL: dodgeroll(delta)
	
	move_and_slide()

#endregion

#region ENTER STATE

func enter_run(): 
	#label.text = "run"
	#print("run")
	
	if not jump_buffer.time_left == 0: change_state(states.JUMP)
	
	dash_used = false

func enter_jump():
	#label.text = "jump"
	#print("jump")
	
	if previous_state == states.WALLSLIDE:
		match msg:
			["wall_to_left"]: velocity = Vector2(wall_jump_distance, -jump_force) 
			["wall_to_right"]: velocity = Vector2(-wall_jump_distance, -jump_force) 
		
	else: velocity.y = -jump_force
	
	jump_sfx.play()

func enter_fall(): 
	#label.text = "fall"
	#print("fall")
	
	if previous_state in [states.RUN, states.CROUCH, states.WALLSLIDE,states.DODGEROLL]: cayote_time.start() 
	
	if variable_jump == 2: velocity.y = 0

func enter_dash(): 
	#label.text = "dash"
	#print("dash")
	velocity = Vector2(cos(gun.rotation),sin(gun.rotation)).normalized() * dash_speed
	
	get_parent().add_child(blast_vfx.instantiate())
	blast_collision.disabled = false
	Input.start_joy_vibration(0,1,1,0.175)
	
	dash_time.wait_time = dash_length * (abs(cos(gun.rotation)) + 1)
	dash_time.start()
	
	dash_used = true

func enter_crouch():
	#label.text = "crouch"
	#print("crouch")
	
	body.position.y = -17
	body.scale.y = 65.18

func enter_wallslide():
	#label.text = "wallslide"
	#print("wallslide")
	
	dash_used = false

func enter_dodgeroll():
	#label.text = "dodgeroll"
	#print("dodgeroll")
	
	body.position.y = -17
	body.scale.y = 65.18
	
	if Input.is_action_pressed("ls_right"): velocity.x = dodge_speed
	elif Input.is_action_pressed("ls_left"): velocity.x = -dodge_speed
	elif gun.flip_v == true: velocity.x = -dodge_speed
	else: velocity.x = dodge_speed
	
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	dodge_time.start()

#endregion

#region STATE PROCESS

func run(delta):
	
	move(speed, acceleration, deceleration, delta)
	aim()
	shoot()
	
	if Input.is_action_just_pressed("jump"): change_state(states.JUMP)
	elif not is_on_floor(): change_state(states.FALL)
	elif ls_zone == 7 : change_state(states.CROUCH)
	elif Input.is_action_just_pressed("dash") and has_dash: change_state(states.DASH)
	elif Input.is_action_just_pressed("dodgeroll"): change_state(states.DODGEROLL)

func jump(delta):
	
	move(speed, airborne_acceleration, airborne_deceleration, delta)
	aim()
	shoot()
	
	if velocity.y > 0:
		
		if hang_time and hang_timer.time_left == 0: hang_timer.start()
		else: change_state(states.FALL)
		
	elif Input.is_action_just_released("jump") and not variable_jump == 0: change_state(states.FALL)
	
	if hang_time:
		if hang_timer.time_left == 0 and velocity.y == 0: change_state(states.FALL)
		elif hang_timer.time_left == 0: velocity.y += ascend
		else: velocity.y = 0
	else: velocity.y += ascend
	
	if Input.is_action_just_pressed("jump"): jump_buffer.start()
	
	if Input.is_action_just_pressed("dash") and not dash_used and has_dash: change_state(states.DASH)
	elif  is_on_floor(): change_state(states.RUN)
	elif is_on_wall() and has_wallslide: change_state(states.WALLSLIDE)

func fall(delta):
	
	move(speed, airborne_acceleration, airborne_deceleration, delta)
	aim()
	shoot()
	
	if velocity.y < max_fall_speed: velocity.y += descend
	
	if Input.is_action_just_pressed("jump"):
		jump_buffer.start()
		if not cayote_time.time_left == 0: change_state(states.JUMP)
	
	if Input.is_action_just_pressed("dash") and not dash_used and has_dash: change_state(states.DASH)
	elif is_on_floor(): change_state(states.RUN)
	elif is_on_wall() and has_wallslide: change_state(states.WALLSLIDE)


func dash(_delta): 
	
	blast_collision.disabled = true
	
	if dash_time.time_left == 0: 
		if is_on_floor() and ls_zone == 7: change_state(states.CROUCH)
		elif is_on_floor(): change_state(states.RUN)
		elif is_on_wall(): change_state(states.WALLSLIDE)
		else: change_state(states.FALL)

func crouch(delta):
	
	move(0, acceleration, deceleration, delta)
	aim()
	shoot()
	
	if Input.is_action_just_pressed("dash") and has_dash: 
		var this_blast_vfx = blast_vfx.instantiate()
		get_parent().add_child(this_blast_vfx)
		this_blast_vfx.global_position = blast_area.global_position
		this_blast_vfx.rotation = gun.rotation
		blast_collision.disabled = false
		Input.start_joy_vibration(0,0.8,0.8,0.175)
	else: blast_collision.disabled = true
	
	if Input.is_action_just_pressed("jump") or not jump_buffer.time_left == 0: change_state(states.JUMP)
	elif not ls_zone == 7 : change_state(states.RUN)
	elif Input.is_action_just_pressed("dodgeroll"): change_state(states.DODGEROLL)
	elif not is_on_floor():
		cayote_time.start()
		change_state(states.FALL)

func wallslide(_delta):
	
	aim()
	shoot()
	
	if velocity.y < wallslide_speed: velocity.y += descend
	else: velocity.y = wallslide_speed
	
	if get_wall_normal().x == 1: 
		velocity.x = -1
		msg = ["wall_to_left"]
	elif get_wall_normal().x == -1:
		velocity.x = 1
		msg = ["wall_to_right"]
	
	if is_on_floor(): change_state(states.RUN)
	elif Input.is_action_just_pressed("dash") and has_dash: change_state(states.DASH)
	elif Input.is_action_just_pressed("jump") or not jump_buffer.time_left == 0: change_state(states.JUMP)
	elif  not is_on_wall(): change_state(states.FALL)
	elif get_wall_normal().x == 1 and Input.is_action_pressed("ls_right"): change_state(states.FALL)
	elif get_wall_normal().x == -1 and Input.is_action_pressed("ls_left"): change_state(states.FALL)

func dodgeroll(_delta):
	
	if Input.is_action_just_pressed("jump"): jump_buffer.start()
	
	if not is_on_floor(): change_state(states.FALL)
	elif dodge_time.time_left == 0: change_state(states.RUN)

#endregion

#region EXIT STATE

func exit_run(): pass

func exit_jump():
	if hang_time: hang_timer.stop()
	msg = []

func exit_fall(): pass

func exit_dash(): pass

func exit_crouch():
	body.position.y = -38
	body.scale.y = 108

func exit_wallslide(): 
	pass

func exit_dodgeroll():
	body.position.y = -38
	body.scale.y = 108
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)

#endregion

#region FUNCTIONS 

func aim():
	
	if not burst_in_use:
		
		if Input.get_axis("rs_left","rs_right") == 0 and Input.get_axis("rs_down","rs_up") == 0:
			
			if Input.is_action_pressed("ls_right"): 
				gun.rotation = PI
				rs_zone = 5
			elif Input.is_action_pressed("ls_left"): 
				gun.rotation = 0
				rs_zone = 1
			elif gun.flip_v == true: 
				gun.rotation = 0
				rs_zone = 1
			else: 
				gun.rotation = PI
				rs_zone = 5
			
		else:
			var rs_angle = Vector2(0,0).angle_to_point(Vector2(Input.get_axis("rs_left","rs_right"),Input.get_axis("rs_down","rs_up")))
			
			if aiming == 0:
				
				if rs_angle > 0.875 * PI:
					gun.rotation = 0
					rs_zone = 1
				elif rs_angle > 0.625 * PI and has_aiming_schematic:
					gun.rotation = 0.25 * PI
					rs_zone = 2
				elif rs_angle > 0.375 * PI and has_aiming_schematic:
					gun.rotation = 0.5 * PI 
					rs_zone = 3
				elif rs_angle > 0.125 * PI and has_aiming_schematic:
					gun.rotation = 0.75 * PI
					rs_zone = 4
				elif rs_angle > -0.125 * PI:
					gun.rotation = PI
					rs_zone = 5
				elif rs_angle > -0.375 * PI and has_aiming_schematic:
					gun.rotation = 1.25 * PI
					rs_zone = 6
				elif rs_angle > -0.625 * PI and has_aiming_schematic:
					gun.rotation = 1.5 * PI
					rs_zone = 7
				elif rs_angle > -0.875 * PI and has_aiming_schematic:
					gun.rotation = 1.75 * PI
					rs_zone = 8
				else:
					gun.rotation = 0
					rs_zone = 1
				
			else: gun.rotation = PI - rs_angle
		
		if gun.flip_v == false: 
			if gun.rotation < 1.5 or gun.rotation > 5: gun.flip_v = true
		else: 
			if gun.rotation < 4.5 and gun.rotation > 1.9: gun.flip_v = false
	
	
	if Input.get_axis("ls_left","ls_right") == 0 and Input.get_axis("ls_down","ls_up") == 0: 
		ls_zone = 0
	else:
		var ls_angle = Vector2(0,0).angle_to_point(Vector2(Input.get_axis("ls_left","ls_right"),Input.get_axis("ls_down","ls_up")))
		
		if ls_angle > 0.875 * PI:
			ls_zone = 1
		elif ls_angle > 0.625 * PI:
			ls_zone = 2
		elif ls_angle > 0.375 * PI:
			ls_zone = 3
		elif ls_angle > 0.125 * PI:
			ls_zone = 4
		elif ls_angle > -0.125 * PI:
			ls_zone = 5
		elif ls_angle > -0.375 * PI:
			ls_zone = 6
		elif ls_angle > -0.625 * PI:
			ls_zone = 7
		elif ls_angle > -0.875 * PI:
			ls_zone = 8
		else:
			ls_zone = 1

func shoot():
	 
	if state in [states.RUN, states.WALLSLIDE]: burst_used = false
	
	if Input.is_action_pressed("burst") and burst_cooldown.time_left == 0 and has_burst and not burst_used: 
		burst_in_use = true
		bullets_shot = 0
	
	if burst_in_use == true: 
		
		if not is_on_floor() and not is_on_wall(): change_state(states.FALL)
		Input.start_joy_vibration(0,0.4,0,0.1)
		burst_cooldown.start()
		
		if shoot_cooldown.time_left == 0 and bullets_shot < 3:
			
			burst_bullet_sfx.pitch_scale = randf_range(0.5,0.7)
			burst_bullet_sfx.play()
			var this_bullet = burst_bullet.instantiate()
			get_parent().add_child(this_bullet)
			
			if not state == states.CROUCH: 
				
				match bullets_shot:
					0: 
						velocity.y = -this_bullet.velocity.normalized().y * 900
						
						if abs(velocity.x) + abs(this_bullet.velocity.normalized().x * 900) < 750:
							velocity.x -= this_bullet.velocity.normalized().x * 900
						else: velocity.x = -this_bullet.velocity.normalized().x * 750
					1: 
						velocity.y = -this_bullet.velocity.normalized().y * 400
						
						if abs(velocity.x) + abs(this_bullet.velocity.normalized().x * 400) < 1000:
							velocity.x -= this_bullet.velocity.normalized().x * 400
						else: velocity.x = -this_bullet.velocity.normalized().x * 1000
					2: 
						velocity.y = -this_bullet.velocity.normalized().y * 750
						
						if abs(velocity.x) + abs(this_bullet.velocity.normalized().x * 750) < 1000:
							velocity.x -= this_bullet.velocity.normalized().x * 750
						else: velocity.x = -this_bullet.velocity.normalized().x * 750
			
			bullets_shot += 1
			shoot_cooldown.start()
			
		elif bullets_shot == 3: 
			burst_used = true
			burst_in_use = false
	
	if Input.is_action_pressed("shoot") and shoot_cooldown.time_left == 0: 
		
		bullet_sfx.pitch_scale = randf_range(0.9,1.1)
		bullet_sfx.play()
		shoot_cooldown.start()
		get_parent().add_child(bullet.instantiate())
		if rs_zone == 7 and velocity.y > 0: velocity.y = 0 
		Input.start_joy_vibration(0,0.4,0,0.1)

func move(current_speed, current_acceleration, current_deceleration, delta):
	
	var final_velocity
	
	if state == states.CROUCH: 
		final_velocity = 0.0
		
	elif variable_speed == 0:
		
		if Input.is_action_pressed("ls_right"): final_velocity = current_speed
		elif Input.is_action_pressed("ls_left"): final_velocity = -current_speed
		else: final_velocity = 0.0
		
	elif variable_speed == 1:
		if Input.get_action_strength("ls_right") > 0.5: final_velocity = current_speed
		elif Input.get_action_strength("ls_left") > 0.5: final_velocity = -current_speed
		elif Input.is_action_pressed("ls_right"): final_velocity = current_speed/2
		elif Input.is_action_pressed("ls_left"): final_velocity = -current_speed/2
		else: final_velocity = 0.0
		
	elif variable_speed == 2: final_velocity = Input.get_axis("ls_left","ls_right") * current_speed
	
	if velocity.x > 0 and velocity.x < final_velocity or velocity.x < 0 and velocity.x > final_velocity or velocity.x == 0:
		velocity.x = lerp(velocity.x, final_velocity, current_acceleration * delta)
	else: 
		velocity.x = lerp(velocity.x, final_velocity, current_deceleration * delta)

#endregion

#region SIGNALS

func _on_hurtbox_body_shape_entered(_body_rid: RID, _body: Node2D, _body_shape_index: int, _local_shape_index: int) -> void:
	position = Vector2(3221.0,10196.001)

#endregion
