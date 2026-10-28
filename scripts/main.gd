extends Node3D

## 胴上げ体験VR - メインスクリプト
## WebXR経由でQuest 3のブラウザからVRセッションを開始し、
## プレイヤーの頭(Rig)を選手たちの胴上げに合わせて上下させる。

const LYING_HEIGHT := 0.15 ## 床に寝た状態の視点高さ(開始前/終了後の待機ポーズ)
const BASE_HEIGHT := 0.9 ## 選手の腰くらいの高さ(トス中の基準高度)
const LIFT_DURATION := 0.5 ## 寝た状態からトスの基準高度まで持ち上がる時間
const TOSS_HEIGHT := 1.6
const TOSS_DURATION := 1.1
const TOSS_COUNT := 9
const ARM_SWING_DEGREES := 110.0
const TEAMMATE_COUNT := 8
const CIRCLE_RADIUS := 1.8
const MOUSE_SENSITIVITY := 0.0028

enum State { WAITING, TOSSING, FINISHED }

@onready var rig: Node3D = $Rig
@onready var xr_camera: XRCamera3D = $Rig/XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $Rig/XROrigin3D/LeftController
@onready var right_controller: XRController3D = $Rig/XROrigin3D/RightController
@onready var world: Node3D = $World
@onready var ui_panel: Control = $UI/Panel
@onready var status_label: Label = $UI/Panel/VBox/StatusLabel
@onready var enter_button: Button = $UI/Panel/VBox/EnterVRButton
@onready var retry_button: Button = $UI/Panel/VBox/RetryButton
@onready var cheer_player: AudioStreamPlayer = $CheerPlayer

var webxr_interface: XRInterface
var vr_supported := false
var teammate_arms: Array[Node3D] = []
var confetti: CPUParticles3D
var active_tween: Tween
var _toss_current_height := TOSS_HEIGHT
var state: State = State.WAITING

## デスクトップでの確認用(実機Quest3ではヘッドトラッキングが代わりに効く)
var in_desktop_preview := false
var _look_yaw := 0.0
var _look_pitch := 0.0


func _ready() -> void:
	_apply_japanese_font()
	_build_stadium()
	_build_teammates()
	_build_confetti()
	_setup_webxr()
	rig.position.y = LYING_HEIGHT
	enter_button.pressed.connect(_on_enter_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	left_controller.button_pressed.connect(_on_controller_button_pressed)
	right_controller.button_pressed.connect(_on_controller_button_pressed)


func _apply_japanese_font() -> void:
	# Godot標準フォントは日本語グリフを含まないため、UIテキストが文字化けする。
	# Noto Sans JP をテーマのデフォルトフォントとして割り当てて解決する。
	var font := load("res://assets/fonts/NotoSansJP-Regular.ttf")
	if font == null:
		return
	var theme := Theme.new()
	theme.default_font = font
	ui_panel.theme = theme


# ---------------------------------------------------------------------------
# WebXR
# ---------------------------------------------------------------------------

func _setup_webxr() -> void:
	webxr_interface = XRServer.find_interface("WebXR")
	if webxr_interface:
		webxr_interface.session_mode = "immersive-vr"
		webxr_interface.requested_reference_space_types = "local-floor"
		webxr_interface.required_features = "local-floor"
		webxr_interface.optional_features = "bounded-floor"
		webxr_interface.session_supported.connect(_on_session_supported)
		webxr_interface.session_started.connect(_on_session_started)
		webxr_interface.session_ended.connect(_on_session_ended)
		webxr_interface.session_failed.connect(_on_session_failed)
		webxr_interface.is_session_supported("immersive-vr")
		status_label.text = "VR対応を確認中..."
	else:
		status_label.text = "このブラウザはWebXR非対応です。\nデスクトップでプレビューします。"
		enter_button.text = "プレビュー開始"
		vr_supported = false


func _on_session_supported(session_mode: String, supported: bool) -> void:
	if session_mode != "immersive-vr":
		return
	vr_supported = supported
	if supported:
		status_label.text = "Quest 3の準備ができました！"
	else:
		status_label.text = "このデバイスはVRに対応していません。\nプレビューのみ可能です。"
		enter_button.text = "プレビュー開始"


func _on_enter_pressed() -> void:
	if webxr_interface and vr_supported:
		status_label.text = "VRセッションを開始します..."
		webxr_interface.initialize()
	else:
		in_desktop_preview = true
		ui_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_enter_waiting_pose()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER):
		_confirm_pressed()
		return
	if not in_desktop_preview:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_look_pitch = clamp(_look_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.3, 1.3)
		rig.rotation.y = _look_yaw
		xr_camera.rotation.x = _look_pitch


## 面ボタン(A/X, B/Y)のみを操作対象にする。トリガーやグリップは
## コントローラーを握っているだけで押下判定になり続けるため対象外。
const CONFIRM_BUTTON_NAMES := ["ax_button", "by_button"]
const CONFIRM_COOLDOWN_MSEC := 700
var _last_confirm_msec := 0


func _on_controller_button_pressed(button_name: String) -> void:
	if not CONFIRM_BUTTON_NAMES.has(button_name):
		return
	_confirm_pressed()


func _confirm_pressed() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_confirm_msec < CONFIRM_COOLDOWN_MSEC:
		return
	_last_confirm_msec = now
	match state:
		State.WAITING, State.FINISHED:
			_start_toss_sequence()
		_:
			pass


func _enter_waiting_pose() -> void:
	state = State.WAITING
	rig.position.y = LYING_HEIGHT
	status_label.text = "Aボタン(またはSpaceキー)で胴上げ開始"


func _on_session_started() -> void:
	get_viewport().use_xr = true
	ui_panel.visible = false
	_enter_waiting_pose()


func _on_session_ended() -> void:
	get_viewport().use_xr = false
	ui_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status_label.text = "VRセッションが終了しました"


func _on_session_failed(message: String) -> void:
	status_label.text = "VR開始に失敗しました: %s" % message


func _on_retry_pressed() -> void:
	retry_button.visible = false
	ui_panel.visible = false
	if in_desktop_preview:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_start_toss_sequence()


# ---------------------------------------------------------------------------
# 胴上げシーケンス
# ---------------------------------------------------------------------------

func _start_toss_sequence() -> void:
	state = State.TOSSING
	ui_panel.visible = false
	confetti.emitting = false
	confetti.restart()
	confetti.emitting = true
	if cheer_player.stream:
		cheer_player.play()

	active_tween = create_tween()
	# 寝た状態から選手に抱え上げられる動き
	active_tween.tween_property(rig, "position:y", BASE_HEIGHT, LIFT_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in range(TOSS_COUNT):
		var is_last := i == TOSS_COUNT - 1
		var height := TOSS_HEIGHT * 1.5 if is_last else TOSS_HEIGHT
		var duration := TOSS_DURATION * 1.4 if is_last else TOSS_DURATION
		active_tween.tween_callback(_set_toss_height.bind(height))
		active_tween.tween_method(_update_toss, 0.0, 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_callback(_on_toss_sequence_finished)


func _set_toss_height(h: float) -> void:
	_toss_current_height = h


func _update_toss(t: float) -> void:
	var h := BASE_HEIGHT + sin(t * PI) * _toss_current_height
	rig.position.y = h
	for arm in teammate_arms:
		arm.rotation_degrees.x = -sin(t * PI) * ARM_SWING_DEGREES


func _on_toss_sequence_finished() -> void:
	state = State.FINISHED
	var down_tween := create_tween()
	down_tween.tween_property(rig, "position:y", LYING_HEIGHT, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	status_label.text = "優勝おめでとうございます！ 🎉\nAボタン(またはSpaceキー)でもう一度"
	ui_panel.visible = true
	enter_button.visible = false
	retry_button.visible = true
	if in_desktop_preview:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------------------
# 選手(胴上げメンバー)の生成
# ---------------------------------------------------------------------------

func _build_teammates() -> void:
	teammate_arms.clear()
	var jersey_mat := StandardMaterial3D.new()
	jersey_mat.albedo_color = Color(0.1, 0.35, 0.75)
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.86, 0.7, 0.57)

	for i in range(TEAMMATE_COUNT):
		var angle := TAU * float(i) / float(TEAMMATE_COUNT)
		var pos := Vector3(sin(angle) * CIRCLE_RADIUS, 0.0, cos(angle) * CIRCLE_RADIUS)

		var teammate := Node3D.new()
		world.add_child(teammate)
		teammate.position = pos
		teammate.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)

		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.height = 1.5
		cap.radius = 0.28
		body.mesh = cap
		body.material_override = jersey_mat
		body.position = Vector3(0, 0.95, 0)
		teammate.add_child(body)

		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		head.mesh = sphere
		head.material_override = skin_mat
		head.position = Vector3(0, 1.85, 0)
		teammate.add_child(head)

		# 肩のピボット。トス中にX回転で腕を振り上げる。
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(0, 1.3, -0.25)
		teammate.add_child(arm_pivot)

		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.15, 0.7, 0.15)
		arm.mesh = arm_mesh
		arm.material_override = jersey_mat
		arm.position = Vector3(0, -0.35, 0)
		arm_pivot.add_child(arm)

		teammate_arms.append(arm_pivot)


# ---------------------------------------------------------------------------
# 球場(プレースホルダー)の生成
# ---------------------------------------------------------------------------

func _build_stadium() -> void:
	# グラウンド(芝)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(80, 80)
	ground.mesh = ground_mesh
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.22, 0.55, 0.25)
	ground.material_override = grass_mat
	world.add_child(ground)

	# 内野(土)
	var infield := MeshInstance3D.new()
	var infield_mesh := PlaneMesh.new()
	infield_mesh.size = Vector2(22, 22)
	infield.mesh = infield_mesh
	infield.position = Vector3(0, 0.01, 0)
	infield.rotation_degrees.y = 45
	var dirt_mat := StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.72, 0.5, 0.33)
	infield.material_override = dirt_mat
	world.add_child(infield)

	# 観客スタンド(4方向)
	var stand_mat := StandardMaterial3D.new()
	stand_mat.albedo_color = Color(0.65, 0.65, 0.7)
	var stand_configs := [
		{"pos": Vector3(0, 4, -32), "rot": 0.0},
		{"pos": Vector3(0, 4, 32), "rot": 180.0},
		{"pos": Vector3(-32, 4, 0), "rot": 90.0},
		{"pos": Vector3(32, 4, 0), "rot": -90.0},
	]
	for cfg in stand_configs:
		var stand := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(50, 8, 10)
		stand.mesh = box
		stand.material_override = stand_mat
		stand.position = cfg["pos"]
		stand.rotation_degrees.y = cfg["rot"]
		stand.rotation_degrees.x = -15
		world.add_child(stand)
		_build_crowd_dots(stand)

	# 照明塔
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.3, 0.3, 0.3)
	var tower_positions := [
		Vector3(-35, 0, -35), Vector3(35, 0, -35),
		Vector3(-35, 0, 35), Vector3(35, 0, 35),
	]
	for tp in tower_positions:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = 20
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.5
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position = tp + Vector3(0, 10, 0)
		world.add_child(pole)

		var spot := SpotLight3D.new()
		var spot_pos: Vector3 = tp + Vector3(0, 20, 0)
		spot.position = spot_pos
		spot.look_at_from_position(spot_pos, Vector3.ZERO, Vector3.UP)
		spot.spot_range = 70
		spot.light_energy = 2.0
		world.add_child(spot)


func _build_crowd_dots(stand: MeshInstance3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.5, 0.4)
	mm.mesh = box

	var count := 400
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(count):
		var x := rng.randf_range(-24.0, 24.0)
		var y := rng.randf_range(-3.5, 3.5)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, y, 5.05)))
		mm.set_instance_color(i, Color(rng.randf(), rng.randf(), rng.randf()))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stand.add_child(mmi)


# ---------------------------------------------------------------------------
# 紙吹雪
# ---------------------------------------------------------------------------

func _build_confetti() -> void:
	# Compatibility(WebGL2)レンダラーはGPUParticlesをサポートしないため CPUParticles3D を使用
	confetti = CPUParticles3D.new()
	confetti.emitting = false
	confetti.amount = 200
	confetti.lifetime = 4.0
	confetti.one_shot = true
	confetti.position = Vector3(0, 8, 0)
	confetti.spread = 180.0
	confetti.direction = Vector3(0, -1, 0)
	confetti.initial_velocity_min = 0.5
	confetti.initial_velocity_max = 2.0
	confetti.gravity = Vector3(0, -2.0, 0)
	confetti.scale_amount_min = 0.5
	confetti.scale_amount_max = 1.2
	confetti.color = Color(1.0, 0.85, 0.2)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	confetti.mesh = mesh

	world.add_child(confetti)
