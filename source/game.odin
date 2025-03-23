package game

import "core:c"
import "core:fmt"
// import "core:log"
import ease "core:math/ease"
import rlights "rlights"
import rl "vendor:raylib"

import sa "core:container/small_array"
import "core:encoding/csv"
import "core:math"
import "core:os"
import "core:strconv"


// bm- state

room_models: [ModelList]RoomModel
level: Level
light_c_tween_i: int
death_cam_tween_i: int
death_screen_tween_i: int
gui_timer_tween_i: int
win_state_tween_i: int

run: bool

cam: rl.Camera

grid_pos: GridCoord
look_at: LookAt
shader: rl.Shader
post_process_shader: rl.Shader
render_texture: rl.RenderTexture2D
dither_mask_texture: rl.Texture2D
dither_tex_loc: i32
lights: [rlights.MAX_LIGHTS]rlights.Light

music: rl.Music
death_anim_timer: f32

soundfxs: [SoundEffect]rl.Sound

// to know which footstep to play
footstep_right: bool

// tween state

// tween for movement
start_pos: rl.Vector3
target_pos: rl.Vector3
current_t: f32

// tween for cam rotation
start_lookat: rl.Vector3
target_lookat: rl.Vector3
current_lookat_t: f32

plane_mesh: rl.Mesh
level_material: rl.Material

clock_texture: rl.Texture
font: rl.Font

// state needed to be reset, other than level cells
frame_counter: int
timer_started: bool
game_timer: f32
won_game: bool
display_fps: bool
muted: bool

// bm- structures

// time left before the clock shows up
clock_gui_tween_length :: 15

game_time_length :: 60 * 2 + 30 // 150
// set it to 30
clock_gui_appear_time :: 30
// to test clock
// clock_gui_appear_time :: game_time_length
// clock_gui_tween_length :: 0.1

// dimensions of level
row_count :: 29
column_count :: 36

death_length :: 2
LevelLayerData :: [][]int
GridCoord :: [2]int // col_i, row_i

LookAt :: enum {
	North,
	South,
	East,
	West,
}

CellState :: struct {
	turned_on:          bool,
	anim_current_frame: i32,
}

Level :: struct {
	level_meshes:     LevelLayerData,
	orientation_data: LevelLayerData,
	connections:      LevelLayerData,
	spawn_point:      GridCoord,
	goal_coord:       GridCoord,
	cells:            [][]CellState,
}

ModelList :: enum {
	FLOOR,
	WALL,
	GATE,
	SWITCH,
	SPIKES,
	DART,
}

SoundEffect :: enum {
	GRUNT,
	WHOOSH,
	GATE_OPEN,
	LEVER_ACTIVATE,
	LEVER_ACTIVATE2,
	WALKING1,
	WALKING2,
	DART,
	PIERCE,
}

// Model information
RoomModel :: struct {
	model:       rl.Model,
	animations:  [^]rl.ModelAnimation,
	// for now, a global frame index. later if needed, this value will have to go for each level cell.
	anim_index:  i32,
	anims_count: i32,

	// turned_on:          bool, // for gates, true if open, false if closed
	// anim_current_frame: i32,
}

get_layer_data :: proc(filename: string) -> (layer_data: LevelLayerData, ok: bool) {
	r: csv.Reader
	r.trim_leading_space = true
	r.reuse_record = true // Without it you have to delete(record)
	r.reuse_record_buffer = true // Without it you have to each of the fields within it
	defer csv.reader_destroy(&r)

	csv_data, ok_file := read_entire_file(filename)
	if ok_file {
		csv.reader_init_with_string(&r, string(csv_data))
	} else {
		fmt.printfln("Unable to open file: %v", filename)
		return
	}
	defer delete(csv_data)

	rows := make_slice(LevelLayerData, row_count)

	for r, row_i, err in csv.iterator_next(&r) {
		if err != nil { /* Do something with error */}

		// begin constructing row
		row := make_slice([]int, column_count)

		for value, column in r {
			if value == "" do continue
			// fmt.printfln(value)
			value_n := strconv.parse_int(value) or_return
			row[column] = value_n
		}

		rows[row_i] = row
	}

	return rows, true
}

load_level_from_ldtk :: proc(level: ^Level) -> (ok: bool) {

	meshes_filename :: "assets/map/simplified/Level_0/Walls.csv"
	orientation_filename :: "assets/map/simplified/Level_0/Orientation.csv"
	misc_filename :: "assets/map/simplified/Level_0/Misc.csv"
	connections_filename :: "assets/map/simplified/Level_0/Connections.csv"

	level.level_meshes = get_layer_data(meshes_filename) or_return
	level.orientation_data = get_layer_data(orientation_filename) or_return
	level.connections = get_layer_data(connections_filename) or_return

	// processing CellState
	level.cells = make_slice([][]CellState, len(level.level_meshes))

	for row, i in level.cells {
		level.cells[i] = make_slice([]CellState, len(level.level_meshes[0]))
	}

	// processing misc
	{
		r: csv.Reader
		r.trim_leading_space = true
		r.reuse_record = true // Without it you have to delete(record)
		r.reuse_record_buffer = true // Without it you have to each of the fields within it
		defer csv.reader_destroy(&r)

		csv_data, ok_file := read_entire_file(misc_filename)
		if ok_file {
			csv.reader_init_with_string(&r, string(csv_data))
		} else {
			fmt.printfln("Unable to open file: %v", misc_filename)
			return
		}
		defer delete(csv_data)

		outer: for r, row_i, err in csv.iterator_next(&r) {
			if err != nil { /* Do something with error */}

			// begin constructing row

			for value, column in r {
				if value == "" do continue
				// fmt.printfln(value)
				value_n := strconv.parse_int(value) or_return

				if value_n == 1 {
					// this is the spawn point
					level.spawn_point = {column, row_i}
				}

				if value_n == 2 {
					level.goal_coord = {column, row_i}
				}
			}
		}

	}

	return true
}

get_cell_world_pos :: proc(x, y: int) -> rl.Vector3 {
	return {f32(x) * 2, 0, f32(y) * 2}
}


draw_all_switch_collisions :: proc() {
	for row, ri in level.level_meshes {
		for val, ci in row {
			cell_type := level.level_meshes[ri][ci]
			if number_to_model(cell_type) == .SWITCH {
				draw_collision(ri, ci)
			}
		}
	}
}

get_collision_sphere_for_switch :: proc(
	row_i, col_i: int,
) -> (
	sphere_pos: rl.Vector3,
	sphere_rad: f32,
) {
	// drawing the collision sphere so u can click on it
	// world_pos := get_cell_world_pos(row_i, column_i)
	world_pos := get_cell_world_pos(col_i, row_i)
	world_pos.y = 2
	orientation := level.orientation_data[row_i][col_i]

	// u gotta offset it based on the rotation...
	switch orientation {
	case 0, 1:
	// north
	case 2:
		// south
		world_pos.z -= 1
	case 3:
		// east
		// rotAngle = 90 * 1
		// TODO
		world_pos.x -= 1
	case 4:
		// west
		// rotAngle = 90 * 3
		world_pos.x += 1
	}

	return world_pos, 0.3
}

// for the switch
draw_collision :: proc(row_i, col_i: int) {
	sp, sr := get_collision_sphere_for_switch(row_i, col_i)
	rl.DrawSphere(sp, sr, rl.WHITE)
}

check_lever_click :: proc(mouse_ray: rl.Ray, row_i, col_i: int) {
	// lever
	// it's a lever. check for mouse interaction
	sp, sr := get_collision_sphere_for_switch(row_i, col_i)
	col := rl.GetRayCollisionSphere(mouse_ray, sp, sr)
	if col.hit && col.distance > 0 {
		flip_switch(row_i, col_i)
	}
}

die :: proc() {
	// if already dead, do nothing
	if death_anim_timer > 0 do return
	death_anim_timer = death_length
	rl.PlaySound(soundfxs[.GRUNT])
}

reset_game :: proc() {
	// restart music
	rl.StopMusicStream(music)

	// resetting world
	for row in level.cells {
		for &v in row {
			v = {}
		}
	}

	frame_counter = 0
	timer_started = false
	game_timer = 0
	won_game = false

	// reset timer tween
	tween_reset(gui_timer_tween_i, paused = true)
	tween_reset(win_state_tween_i, paused = true)

	position_at_spawn()
}

is_at_dart_range :: proc(
	coord: GridCoord,
) -> (
	hit_by_dart: bool,
	dart_pos: GridCoord,
	dir: LookAt,
) {

	// get 4 adjacent tiles

	// for each:
	//   if it's dart tile and pointing at you, then true

	// loop
	for i in 0 ..< 4 {
		test_coord: GridCoord

		switch i {
		case 0:
			test_coord = GridCoord{coord.x, coord.y + 1}
			dir = .North
		case 1:
			test_coord = GridCoord{coord.x, coord.y - 1}
			dir = .South
		case 2:
			test_coord = GridCoord{coord.x - 1, coord.y}
			dir = .East
		case 3:
			test_coord = GridCoord{coord.x + 1, coord.y}
			dir = .West
		}

		mt := level.level_meshes[test_coord.y][test_coord.x]

		if number_to_model(mt) != .DART do continue

		// test if dart is pointing towards coord

		or := level.orientation_data[test_coord.y][test_coord.x]
		if or == 0 do or = 1
		if i + 1 == or do return true, test_coord, dir
	}

	// then false

	return false, dart_pos, look_at

}

start_timer :: proc() {
	rl.StopMusicStream(music)
	rl.PlayMusicStream(music)
	timer_started = true
	game_timer = 0
}

// 720p
// window_width :: 1280
// window_height :: 720

// 480p
render_width :: 640
render_height :: 480

// window starting size
window_start_width :: render_width * 2
window_start_height :: render_height * 2

handle_goal :: proc(coord: GridCoord) -> bool {
	if coord != level.goal_coord {
		return false
	}

	rl.StopMusicStream(music)

	timer_started = false
	// game_timer = 0
	won_game = true

	tween_reset(win_state_tween_i, paused = false)

	// reached goal. do something
	return true
}

draw_end_text :: proc(t: ^Tween) {

	line_count := f32(0)
	x_start := f32(50)

	text_scale: f32 = 0.005 * f32(rl.GetScreenHeight())
	y_step: f32 = text_scale * 25
	y_start: f32 = text_scale * 50

	text_col: rl.Color = {255, 255, 255, 150}

	sw := f32(rl.GetScreenWidth())

	speed_step :: 0.15
	// speed_step :: 0

	// As the stone shifts
	// The cycle continues
	// [time] seconds

	if t.t > 0.2 {
		// if t.t > 0.0 {
		timetxt := rl.TextFormat("Time: %f seconds.", game_timer)
		rl.DrawTextEx(
			font,
			timetxt,
			{sw / 2 - text_scale * 60, y_start + line_count * y_step},
			f32(font.baseSize) * text_scale,
			4,
			text_col,
		)
		line_count += 1
	}


	if t.t > 0.2 + speed_step * line_count {
		// if t.t > 0.0 {
		rl.DrawTextEx(
			font,
			"As the stones shift,",
			{sw / 2 - text_scale * (60 + 60), y_start + line_count * y_step},
			f32(font.baseSize) * text_scale,
			4,
			text_col,
		)
		line_count += 1
	}

	if t.t > 0.2 + speed_step * line_count {
		// if t.t > 0.0 {
		rl.DrawTextEx(
			font,
			"the cycle continues.",
			{sw / 2 + text_scale * 1, y_start + line_count * y_step},
			f32(font.baseSize) * text_scale,
			4,
			text_col,
		)
		line_count += 1
	}
}

init :: proc() {
	run = true
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	// rl.SetConfigFlags({.WINDOW_RESIZABLE})
	// rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(window_start_width, window_start_height, "legend of paths")
	// rl.ToggleBorderlessWindowed()

	clock_texture = rl.LoadTexture("assets/clock.png")
	clock_texture.mipmaps = 1
	rl.SetTextureFilter(clock_texture, .POINT)
	rl.SetTextureWrap(clock_texture, .CLAMP)

	// init font
	font = rl.LoadFont("assets/pixelplay.png")
	// rl.SetTextureFilter(font.texture, .POINT)

	// bm- init audio

	rl.InitAudioDevice()
	// mute everything (for dev)
	// rl.SetMasterVolume(0)

	music = rl.LoadMusicStream("assets/sounds/gamejam.wav")
	music.looping = false

	// load sfx
	for &s, i in soundfxs {
		filename: cstring
		sound_volume: f32 = 1
		switch i {
		case .GRUNT:
			filename = "assets/sounds/grunt.wav"
			sound_volume = 0.5
		case .WHOOSH:
			filename = "assets/sounds/whoosh.wav"
			sound_volume = 0.25
		case .GATE_OPEN:
			filename = "assets/sounds/gate_opening.wav"
		case .LEVER_ACTIVATE:
			filename = "assets/sounds/activate_lever.wav"
		case .LEVER_ACTIVATE2:
			filename = "assets/sounds/activate_lever_2.wav"
		case .WALKING1:
			filename = "assets/sounds/footstep_left.wav"
		case .WALKING2:
			filename = "assets/sounds/footstep_right.wav"
		case .DART:
			filename = "assets/sounds/dart.wav"
			sound_volume = 1.8
		case .PIERCE:
			filename = "assets/sounds/pierce.wav"
		// sound_volume = 1.5
		}
		s = rl.LoadSound(filename)
		rl.SetSoundVolume(s, sound_volume)
	}


	// parse csv
	pok := load_level_from_ldtk(&level)
	if !pok {
		fmt.eprintln("parsed wrong")
		// os.exit(1)
	}

	// // Anything in `assets` folder is available to load.
	// texture = rl.LoadTexture("assets/round_cat.png")

	// // A different way of loading a texture: using `read_entire_file` that works
	// // both on desktop and web. Note: You can import `core:os` and use
	// // `read_entire_file`. But that won't work on web. Emscripten has a way
	// // to bundle files into the build, and we access those using this
	// // special `read_entire_file`.
	// if long_cat_data, long_cat_ok := read_entire_file("assets/long_cat.png", context.temp_allocator); long_cat_ok {
	// 	long_cat_img := rl.LoadImageFromMemory(".png", raw_data(long_cat_data), c.int(len(long_cat_data)))
	// 	texture2 = rl.LoadTextureFromImage(long_cat_img)
	// 	rl.UnloadImage(long_cat_img)
	// }

	/// shader setup

	// Load basic lighting shader

	shader = rl.LoadShader(
		"assets/shaders/lighting.vs",
		"assets/shaders/lighting.fs")
	post_process_shader = rl.LoadShader(
		"assets/shaders/post_process.vs",
		"assets/shaders/post_process.fs",
	)

	render_texture = rl.LoadRenderTexture(render_width, render_height)
	dither_mask_texture = rl.LoadTexture("assets/dither_mask.png")

	dither_tex_loc = rl.GetShaderLocation(post_process_shader, "texture1")
	rw := rl.GetShaderLocation(post_process_shader, "renderWidth")
	rh := rl.GetShaderLocation(post_process_shader, "renderHeight")

	ww_v: f32 = render_width
	wh_v: f32 = render_height
	rl.SetShaderValue(post_process_shader, rw, &ww_v, .FLOAT)
	rl.SetShaderValue(post_process_shader, rh, &wh_v, .FLOAT)

	// Get some required shader locations
	shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW] = rl.GetShaderLocation(shader, "viewPos")
	// NOTE: "matModel" location name is automatically assigned on shader loading, 
	// no need to get the location again if using that uniform name
	//shader.locs[SHADER_LOC_MATRIX_MODEL] = GetShaderLocation(shader, "matModel");

	// Ambient light level (some basic lighting)
	ambientLoc := rl.GetShaderLocation(shader, "ambient")
	ambient_val_u :: 1
	ambient_val := [4]f32{ambient_val_u, ambient_val_u, ambient_val_u, 1.0}

	rl.SetShaderValue(shader, ambientLoc, &ambient_val, .VEC4)

	// Create lights
	// Light lights[MAX_LIGHTS] = { 0 };

	lights[0] = rlights.CreateLight(.Point, {-2, 1, -2}, {}, 1, {219, 207, 191, 255}, shader)
	// lights[1] = rlights.CreateLight(.Point, {2, 1, 2}, {}, rl.RED, shader)
	// lights[2] = rlights.CreateLight(.Point, {-2, 1, 2}, {}, rl.GREEN, shader)
	// lights[3] = rlights.CreateLight(.Point, {2, 1, -2}, {}, rl.BLUE, shader)

	/// bm- tween init

	// create light tween
	light_c_tween_i = tweens.len
	sa.append(
		&tweens,
		Tween {
			from = {0.8, .5, .5},
			to = {1, 1, 1},
			duration = 1.5,
			ttype = .PingPong,
			ease = .Sine_In_Out,
		},
	)

	// create cam death tween
	death_cam_tween_i = tweens.len
	sa.append(
		&tweens,
		Tween{from = {cam_y_pos, .5, .5}, to = {0.4, 0.3, 1}, duration = 0.5, ease = .Quintic_In},
	)

	death_screen_tween_i = tweens.len
	sa.append(
		&tweens,
		Tween {
			from = {0, .5, .5},
			to = {0.6, 0.3, 1},
			duration = death_length,
			ease = .Exponential_Out,
		},
	)

	gui_timer_tween_i = tweens.len
	sa.append(
		&tweens,
		Tween {
			from = {0, .5, .5},
			to = {1, 0.3, 1},
			paused = true,
			duration = clock_gui_tween_length,
			ease = .Sine_Out,
		},
	)

	win_state_tween_i = tweens.len
	sa.append(
		&tweens,
		Tween{from = {}, to = {100, 0, 0}, paused = true, duration = 20, ease = .Quadratic_In},
	)

	apply_shader :: proc(model: rl.Model, shader: rl.Shader) {
		for i in 0 ..< model.materialCount {
			model.materials[i].shader = shader
		}
	}

	for &model, i in room_models {

		mname: cstring

		switch i {
		case .GATE:
			mname = "assets/room_gate.glb"
		case .WALL:
			mname = "assets/room_wall.glb"
		case .FLOOR:
			mname = "assets/room_floor.glb"
		case .SWITCH:
			mname = "assets/room_switch.glb"
		case .SPIKES:
			mname = "assets/room_spikes.glb"
		case .DART:
			mname = "assets/room_dart.glb"
		}

		model.model = rl.LoadModel(mname)
		// loading animations? if it has it
		model.animations = rl.LoadModelAnimations(mname, &model.anims_count)
		apply_shader(model.model, shader)
	}

	plane_mesh = rl.GenMeshCube(0.8, 0.8, 0.8)
	level_material.shader = shader

	position_at_spawn()
	cam_pos := pos_to_cam_pos(grid_pos)
	cam = rl.Camera{cam_pos, cam_pos + get_cam_lookat(look_at), {0, 1, 0}, 80, .PERSPECTIVE}
}

get_cam_lookat :: proc(p_lookat: LookAt) -> rl.Vector3 {
	switch p_lookat {
	case .North:
		return {0, 0, 1}
	case .South:
		return {0, 0, -1}
	case .West:
		return {1, 0, 0}
	case .East:
		return {-1, 0, 0}
	}

	return {}
}

cam_y_pos :: 2

pos_to_cam_pos :: proc(grid_pos: GridCoord) -> rl.Vector3 {
	return {f32(grid_pos.x) * 2, cam_y_pos, f32(grid_pos.y) * 2}
}

apply_t :: proc(start, end, t: f32) -> f32 {
	return start + (end - start) * t
}

apply_t_v3 :: proc(start, end: rl.Vector3, t: f32) -> rl.Vector3 {
	return {
		start.x + (end.x - start.x) * t,
		start.y + (end.y - start.y) * t,
		start.z + (end.z - start.z) * t,
	}
}

number_to_orientation :: proc(num: int) -> (ret: LookAt) {
	switch num {
	case 0, 1:
		ret = .North
	case 2:
		ret = .South
	case 3:
		ret = .East
	case 4:
		ret = .West
	}
	return
}

position_at_spawn :: proc() {
	grid_pos = level.spawn_point
	start_pos = pos_to_cam_pos(grid_pos)
	target_pos = pos_to_cam_pos(grid_pos)
	current_t = 0

	look_at_n := level.orientation_data[grid_pos.y][grid_pos.x]
	switch look_at_n {
	case 0, 1:
		// these won't map to what it says in ldtk because i'm laying out the map wrong
		// this is actually north in ldtk
		look_at = .South
	case 2:
		// this is actually south in ldtk
		look_at = .North
	case 3:
		// this is actually east in ldtk
		look_at = .West
	case 4:
		// this is actually west in ldtk
		look_at = .East
	}

	start_lookat = get_cam_lookat(look_at)
	target_lookat = get_cam_lookat(look_at)
}

number_to_model :: proc(n: int) -> ModelList {
	switch n {
	case 1:
		return .FLOOR
	case 2:
		return .WALL
	case 3:
		return .GATE
	case 4:
		return .SWITCH
	case 5:
		return .SPIKES
	case 6:
		return .DART
	}

	return .FLOOR
}

// returns false if u can't go there
go_to :: proc(pos: GridCoord, dir: LookAt) -> (next_pos: GridCoord, can_go: bool) {

	// pos_v := rl.Vector2 {f32(pos.x), f32(pos.y)}

	switch dir {
	case .North:
		next_pos = pos + {0, 1}
	case .South:
		next_pos = pos + {0, -1}
	case .East:
		next_pos = pos + {-1, 0}
	case .West:
		next_pos = pos + {1, 0}
	}

	// get mesh value of next
	mesh_val := level.level_meshes[next_pos.y][next_pos.x]
	cell_data := level.cells[next_pos.y][next_pos.x]
	// fmt.println(number_to_model(mesh_val))

	// check for tile collision
	switch number_to_model(mesh_val) {
	case .WALL, .DART:
		can_go = false
	case .GATE:
		// check if it's open
		can_go = cell_data.turned_on
	case .FLOOR, .SWITCH, .SPIKES:
		can_go = true
	}


	return next_pos, can_go
}

rotate_left :: proc(dir: LookAt) -> LookAt {
	switch dir {
	case .North:
		return .West
	case .South:
		return .East
	case .East:
		return .North
	case .West:
		return .South
	}

	return .North
}

rotate_right :: proc(dir: LookAt) -> LookAt {
	switch dir {
	case .North:
		return .East
	case .South:
		return .West
	case .East:
		return .South
	case .West:
		return .North
	}

	return .North
}

get_opposite_dir :: proc(dir: LookAt) -> LookAt {
	switch dir {
	case .North:
		return .South
	case .South:
		return .North
	case .East:
		return .West
	case .West:
		return .East
	}

	return .North
}

// draws the model given a coord
// updates its animations based on the level cell data too, if it has animations
draw_model :: proc(model: RoomModel, x, y: int, rot_angle: f32) {

	// update animation
	// if frame_counter % 8 == 0 && model.animations != nil {
	if model.animations != nil {
		anim := model.animations[0]

		cell := &level.cells[y][x]

		if cell.turned_on {
			cell.anim_current_frame = math.min(cell.anim_current_frame + 1, anim.frameCount - 1)
		} else {
			cell.anim_current_frame = math.max(cell.anim_current_frame - 1, 0)
		}

		rl.UpdateModelAnimation(model.model, anim, cell.anim_current_frame)
	}

	// draw model

	rl.DrawModelEx(model.model, {f32(x) * 2, 0, f32(y) * 2}, {0, 1, 0}, rot_angle, 1, rl.WHITE)

}

handle_input :: proc(dt: f32) {
	/// handle input
	new_grid_pos: GridCoord
	new_look_at: LookAt
	moved: bool
	rotated: bool

	if rl.IsKeyPressed(.W) || rl.IsKeyPressed(.UP) || rl.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
		// go towards where u point at
		new_grid_pos, moved = go_to(grid_pos, look_at)
	}
	if rl.IsKeyPressed(.A) ||
	   rl.IsKeyPressed(.LEFT) ||
	   rl.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
		new_look_at = rotate_left(look_at)
		rotated = true
	}
	if rl.IsKeyPressed(.S) ||
	   rl.IsKeyPressed(.DOWN) ||
	   rl.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
		new_grid_pos, moved = go_to(grid_pos, get_opposite_dir(look_at))
	}
	if rl.IsKeyPressed(.D) ||
	   rl.IsKeyPressed(.RIGHT) ||
	   rl.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
		new_look_at = rotate_right(look_at)
		rotated = true
	}

	// strafe input
	if rl.IsKeyPressed(.E) || rl.IsGamepadButtonPressed(0, .RIGHT_TRIGGER_1) {
		new_grid_pos, moved = go_to(grid_pos, rotate_right(look_at))
	}
	if rl.IsKeyPressed(.Q) || rl.IsGamepadButtonPressed(0, .LEFT_TRIGGER_1) {
		new_grid_pos, moved = go_to(grid_pos, rotate_left(look_at))
	}

	if moved {
		// do this for the tween to snap to the grid position always. it will snap
		// start_pos = pos_to_cam_pos(grid_pos)

		if footstep_right {
			rl.PlaySound(soundfxs[.WALKING1])
		} else {
			rl.PlaySound(soundfxs[.WALKING2])
		}

		footstep_right = !footstep_right

		mesh_val := level.level_meshes[new_grid_pos.y][new_grid_pos.x]
		is_dart_at_range_result, dart_pos, look_at_trap := is_at_dart_range(new_grid_pos)
		hit_spikes := number_to_model(mesh_val) == .SPIKES

		if is_dart_at_range_result {
			rl.PlaySound(soundfxs[.DART])
			// rl.PlaySound(soundfxs[.PIERCE])
			cell := &level.cells[dart_pos.y][dart_pos.x]
			cell.turned_on = true
			new_look_at = look_at_trap
			rotated = true

			// look at the dart trap
		}

		if hit_spikes {
			rl.PlaySound(soundfxs[.PIERCE])
		}

		if hit_spikes || is_dart_at_range_result {
			die()
		}

		reached_goal := handle_goal(new_grid_pos)
		if reached_goal {
			rotated = true
			new_look_at = .West
		}

		start_pos = cam.position
		target_pos = pos_to_cam_pos(new_grid_pos)
		current_t = 0
		grid_pos = new_grid_pos
	}

	if rotated {
		rl.PlaySound(soundfxs[.WHOOSH])
		// tween rotation reset
		start_lookat = get_cam_lookat(look_at)
		target_lookat = get_cam_lookat(new_look_at)
		current_lookat_t = 0
		look_at = new_look_at
	}
}

flip_switch :: proc(row_i, col_i: int) {
	// you hit the switch

	// if it's the first switch, the timer starts
	if !timer_started {
		start_timer()
	}

	rl.PlaySound(soundfxs[.LEVER_ACTIVATE2])

	cell := &level.cells[row_i][col_i]
	cell.turned_on = !cell.turned_on

	// query connections

	conn_switch := level.connections[row_i][col_i]
	if conn_switch == 0 do return

	/// open gate if all switches with that connection are turned on

	// all switches with the same connection
	switches_conn: sa.Small_Array(20, GridCoord)

	// all gates with the same connection
	gates_conn: sa.Small_Array(20, GridCoord)

	gate_should_open: bool = true

	for &row, row_i in level.connections {
		for val, col_i in row {
			if val == conn_switch {

				cell_type := level.level_meshes[row_i][col_i]

				if number_to_model(cell_type) == .GATE {
					sa.append(&gates_conn, GridCoord{col_i, row_i})
				}

				if number_to_model(cell_type) == .SWITCH {
					sa.append(&switches_conn, GridCoord{col_i, row_i})

					cell_gate := &level.cells[row_i][col_i]

					if !cell_gate.turned_on {
						gate_should_open = false
					}
				}
			}
		}
	}

	for gate_coord_i in 0 ..< gates_conn.len {
		gate_coord := sa.get(gates_conn, gate_coord_i)

		cell_gate := &level.cells[gate_coord.y][gate_coord.x]

		prev_value := cell_gate.turned_on
		cell_gate.turned_on = gate_should_open

		// the gate flipped. play sound
		if prev_value != cell_gate.turned_on {

			// set volume based on gate distance
			gate_pos := get_cell_world_pos(gate_coord.x, gate_coord.y)
			dist := rl.Vector3Length(cam.position - gate_pos)

			min_dist :: 2
			max_dist :: 16

			min_vol :: 0.2
			max_vol :: 1

			// min_dist + (max_dist - min_dist) * dist
			// (max_dist - min_dist) * dist

			dist = math.clamp(dist, min_dist, max_dist)
			t := (dist - min_dist) / (max_dist - min_dist)

			gate_vol := max_vol + (min_vol - max_vol) * t

			// fmt.println(gate_vol)

			rl.SetSoundVolume(soundfxs[.GATE_OPEN], gate_vol)
			rl.PlaySound(soundfxs[.GATE_OPEN])
		}
	}
}

update :: proc() {
	dt := rl.GetFrameTime()

	if rl.IsKeyPressed(.F) {
		rl.ToggleBorderlessWindowed()
	}

	// handle game timer
	if timer_started {
		game_timer += dt

		if game_timer >= game_time_length - clock_gui_appear_time {
			tween := tween_get(gui_timer_tween_i)
			tween.paused = false
		}

		if game_timer >= game_time_length {
			die()
			timer_started = false
		}
	}

	// handling death
	if death_anim_timer > 0 {
		death_anim_timer -= dt
		if death_anim_timer <= 0 {
			reset_game()
		}
	}

	// update tweens
	tweens_update(dt)

	// do not play tween if not dead
	if death_anim_timer <= 0 {
		tween := tween_get(death_cam_tween_i)
		tween.t = 0
	}
	if death_anim_timer <= 0 {
		tween := tween_get(death_screen_tween_i)
		tween.t = 0
	}

	// update music
	rl.UpdateMusicStream(music)

	if death_anim_timer <= 0 && !won_game {
		handle_input(dt)
	}

	///  update camera

	// rl.UpdateCamera(&cam, .ORBITAL)

	// update pos tween
	tt := ease.ease(.Cubic_Out, current_t)
	cam.position = apply_t_v3(start_pos, target_pos, tt)

	// get y pos from cam death tween
	cam.position.y = tween_get_value(death_cam_tween_i).x

	current_t += dt
	if current_t > 1 {
		current_t = 1
	}

	// update dir tweeen

	tt = ease.ease(.Circular_Out, current_lookat_t)
	lookat_part := apply_t_v3(start_lookat, target_lookat, tt)
	cam.target = cam.position + lookat_part

	current_lookat_t += dt * 2
	if current_lookat_t > 1 {
		current_lookat_t = 1
	}

	/// update shader values

	// UpdateCamera(&camera, CAMERA_ORBITAL);

	// Update the shader with the camera view vector (points towards { 0.0f, 0.0f, 0.0f })
	cameraPos := [3]f32{cam.position.x, cam.position.y, cam.position.z}
	rl.SetShaderValue(shader, shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW], &cameraPos, .VEC3)

	lights[0].position = cam.position + {0, 0.5, 0}
	lights[0].position.x += tween_get_value(win_state_tween_i).x
	lights[0].attenuation = tween_get_value(light_c_tween_i).x

	rlights.UpdateLightValues(shader, lights[0])


	/// bm- mouse checks

	if rl.IsMouseButtonPressed(.LEFT) {
		mouse_ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), cam)
		if level.level_meshes[grid_pos.y][grid_pos.x] == 4 {
			check_lever_click(mouse_ray, grid_pos.y, grid_pos.x)
		}
	}

	// checking space for hit switch

	if rl.IsKeyPressed(.SPACE) || rl.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
		is_in_switch_cell := level.level_meshes[grid_pos.y][grid_pos.x] == 4
		or := number_to_orientation(level.orientation_data[grid_pos.y][grid_pos.x])
		is_looking_at_switch := or == look_at
		if is_looking_at_switch && is_in_switch_cell {
			// flip switch
			flip_switch(grid_pos.y, grid_pos.x)
		}
	}

	/// draw


	//rl.BeginDrawing()
	rl.BeginTextureMode(render_texture)
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode3D(cam)
	rl.BeginShaderMode(shader)

	// rl.DrawModel(map_model, {}, 1, rl.WHITE)

	/// bm- draw level
	for row, row_i in level.level_meshes {
		for value, col_i in row {

			if value == 0 do continue

			transform := rl.Transform {
				translation = {},
				rotation    = rl.Quaternion(1),
				scale       = 1,
			}

			orientation := level.orientation_data[row_i][col_i]
			rotAngle: f32 = 0

			// no rotation points to -Y

			switch orientation {
			case 0, 1:
				// north
				rotAngle = 90 * 2
			case 2:
				// south
				rotAngle = 90 * 0
			case 3:
				// east
				rotAngle = 90 * 1
			case 4:
				// west
				rotAngle = 90 * 3
			}

			value_m := number_to_model(value)

			switch value_m {
			case .FLOOR:
				// floor
				draw_model(room_models[.FLOOR], col_i, row_i, rotAngle)
			case .WALL:
				// wall
				draw_model(room_models[.WALL], col_i, row_i, rotAngle)
			case .GATE:
				draw_model(room_models[.FLOOR], col_i, row_i, rotAngle)
				draw_model(room_models[.GATE], col_i, row_i, rotAngle)
			case .SWITCH:
				draw_model(room_models[.FLOOR], col_i, row_i, rotAngle)
				draw_model(room_models[.SWITCH], col_i, row_i, rotAngle)
			case .SPIKES:
				draw_model(room_models[.SPIKES], col_i, row_i, rotAngle)
			case .DART:
				draw_model(room_models[.DART], col_i, row_i, rotAngle)
			}

			// mesh_matrix := rl.MatrixTranslate()
			// rl.DrawMesh(map_model.meshes[7], level_material, mesh_matrix)
		}
	}

	// debug collisions
	// draw_all_switch_collisions()

	rl.EndShaderMode()

	// drawing light position for debugging
	// for &light in lights {
	// 	if !light.enabled do continue
	// 	rl.DrawSphere(light.position, 0.1, rl.WHITE)
	// }

	// rl.DrawGrid(10, 1)
	rl.EndMode3D()

	//rl.EndDrawing()
	// draw death effect (red screen) 
	{
		alpha_val := tween_get_value(death_screen_tween_i)
		rl.DrawRectangle(0, 0, render_width, render_height, {255, 0, 0, u8(alpha_val.x * 255)})
	}


	rl.EndTextureMode()

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginShaderMode(post_process_shader)
	rl.SetShaderValueTexture(post_process_shader, dither_tex_loc, dither_mask_texture)

	sh := f32(rl.GetScreenHeight())
	sw := f32(rl.GetScreenWidth())
	rh := f32(render_texture.texture.height)
	r_scale: f32 = sh / rh
	rw_scaled := f32(render_texture.texture.width) * r_scale

	rl.DrawTextureEx(render_texture.texture, {sw / 2 - rw_scaled / 2, 0}, 0, sh / rh, rl.BLACK)

	rl.EndShaderMode()

	// draw clock
	{
		clock_texture_scale: f32 = sh * 0.001
		clock_alpha := u8(tween_get_value(gui_timer_tween_i).x * 100)

		// this centers it
		// clock_pos := rl.Vector2{f32(rl.GetScreenWidth()) / 2 - (f32(clock_texture.width) * clock_texture_scale) / 2, 20}

		// this puts it at the right corner
		clock_pos := rl.Vector2 {
			rw_scaled +
			sw / 2 -
			rw_scaled / 2 -
			f32(clock_texture.width) * clock_texture_scale -
			10,
			20,
		}

		rl.DrawTextureEx(
			clock_texture,
			clock_pos,
			0,
			clock_texture_scale,
			{255, 100, 100, clock_alpha},
		)
	}

	if won_game {
		t := tween_get(win_state_tween_i)

		if death_anim_timer <= 0 {
			draw_end_text(t)
		}

		if t.t >= 0.8 {
			die()
		}
	}

	if rl.IsKeyPressed(.M) {
		// toggle mute
		muted = !muted
		if muted {
			rl.SetMasterVolume(0)
		} else {
			rl.SetMasterVolume(1)
		}
	}

	if rl.IsKeyPressed(.KP_ADD) {
		display_fps = !display_fps
	}

	if display_fps {
		rl.DrawText(rl.TextFormat("fps: %v", rl.GetFPS()), 2, 2, 100, rl.WHITE)
	}

	rl.EndDrawing()

	frame_counter += 1

	// Anything allocated using temp allocator is invalid after this.
	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	rl.CloseWindow()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}

	return run
}

// tweens

TweenType :: enum {
	Nothing,
	Loop,
	PingPong,
}

Tween :: struct {
	from:            rl.Vector3,
	to:              rl.Vector3,
	paused:          bool,
	duration:        f32,
	ttype:           TweenType,
	ease:            ease.Ease,
	t:               f32,
	ping_pong_state: bool,
}

tweens: sa.Small_Array(20, Tween)

tween_get_value :: proc(tween_i: int) -> rl.Vector3 {
	tween := sa.get_ptr(&tweens, tween_i)
	tt := ease.ease(tween.ease, tween.t)
	return apply_t_v3(tween.from, tween.to, tt)
}

tween_get :: proc(tween_i: int) -> ^Tween {
	return sa.get_ptr(&tweens, tween_i)
}

tweens_update :: proc(dt: f32) {
	for i in 0 ..< tweens.len {
		tween := sa.get_ptr(&tweens, i)
		if tween.paused do continue
		increment := dt / tween.duration

		switch tween.ttype {
		case .Nothing:
			tween.t = math.min(1, tween.t + increment)
		case .Loop:
			tween.t = math.min(1, tween.t + increment)
			if tween.t >= 1 {
				tween.t = 0
			}
		case .PingPong:
			if tween.ping_pong_state {
				tween.t = math.max(0, tween.t - increment)
				if tween.t <= 0 do tween.ping_pong_state = false
			} else {
				tween.t = math.min(1, tween.t + increment)
				if tween.t >= 1 do tween.ping_pong_state = true
			}
		}
	}
}

tween_reset :: proc(tween_i: int, paused := false) {
	tween := tween_get(tween_i)
	tween.paused = paused
	tween.t = 0
}
