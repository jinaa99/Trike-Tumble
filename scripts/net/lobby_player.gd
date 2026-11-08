class_name LobbyPlayer
extends RefCounted
## One seat in a lobby: a human (local or, later, remote) or an AI racer.

var id := 0
var display_name := ""
var is_host := false
var is_local := false
var is_ai := false
var is_ready := false
var ai_difficulty := AIDriverConfig.Difficulty.MEDIUM
var color := Color.WHITE
