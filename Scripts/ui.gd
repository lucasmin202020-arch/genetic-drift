extends Panel

var game
var btn_start
var btn_pause
var btn_reset

var started: bool = false
var paused: bool = false

func _ready():
	game = get_parent()
	btn_start = $VBox/TopButtons/BtnStart
	btn_pause = $VBox/TopButtons/BtnPause
	btn_reset = $VBox/TopButtons/BtnReset
	btn_pause.disabled = true

func _on_btn_start_pressed():
	if not started:
		started = true
		paused = false
		btn_start.disabled = true
		btn_pause.disabled = false
		btn_pause.text = "Pause"
		game.start_simulation()
	else:
		paused = false
		btn_start.disabled = true
		btn_pause.disabled = false
		btn_pause.text = "Pause"
		game.resume_simulation()

func _on_btn_pause_pressed():
	if not paused:
		paused = true
		btn_pause.disabled = true
		btn_start.text = "Resume"
		btn_start.disabled = false
		game.pause_simulation()

func _on_btn_reset_pressed():
	started = false
	paused = false
	btn_start.text = "Start"
	btn_start.disabled = false
	btn_pause.disabled = true
	btn_pause.text = "Pause"
	game.reset_simulation()

func _on_btn_bottleneck_pressed():
	game.cmd_bottleneck()

func _on_btn_unlucky_death_pressed():
	game.cmd_unlucky_death()

func _on_btn_natural_disaster_pressed():
	game.cmd_natural_disaster()
