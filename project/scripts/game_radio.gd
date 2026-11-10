class_name GameRadio
extends CanvasLayer
## Emisoras en vivo y biblioteca local: recuerda volumen y baja durante diálogos.
const STATIONS := [
	["NUEVA Q · CUMBIA","https://mdstrm.com/audio/6839e1f153fcf56d988d5943/live.m3u8?property=aiir"],
	["RADIOMAR · SALSA","https://mdstrm.com/audio/6839e261d2efddf5bfbc2d3d/live.m3u8?property=aiir"],
	["LA INOLVIDABLE · RECUERDOS","https://mdstrm.com/audio/6839e24cf4eacd81ada4e6b4/live.m3u8?property=aiir"],
	["TU MÚSICA · BIBLIOTECA","user://radio/"]]
var live: PeruLiveRadio
var _playlist: Array[String]=[]
var _track:=0
var player: AudioStreamPlayer
var ambience: AudioStreamPlayer
var label: Label
var station := 0
var enabled := false
var volume := .5
var _duck_left := 0.0
var _message_left := 0.0
var _last_key := 0.0
var world: TerrainWorld
var moto: Mototaxi

func setup(w: TerrainWorld,m: Mototaxi,race: RaceManager) -> void:
	world=w
	moto=m
	layer=8
	station=clampi(int(GameSettings.get_option("emisora",0)),0,STATIONS.size()-1)
	enabled=bool(GameSettings.get_option("radio_encendida",false))
	volume=clampf(float(GameSettings.get_option("radio_volumen",.5)),0,1)
	player=AudioStreamPlayer.new()
	add_child(player)
	live=PeruLiveRadio.new();add_child(live)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://radio/"))
	player.finished.connect(_next_track)
	ambience=AudioStreamPlayer.new()
	ambience.stream=_stream("res://audio/world/rural.wav")
	ambience.volume_db=-38
	add_child(ambience)
	ambience.play()
	label=Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left=-310
	label.offset_right=310
	label.offset_top=-68
	label.offset_bottom=-15
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",15)
	label.add_theme_constant_override("outline_size",5)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	add_child(label)
	race.passenger_said.connect(func(_text): _duck_left=3.5)
	_tune()

func _stream(path: String) -> AudioStream:
	var stream:=load(path) as AudioStream
	if stream==null: return null
	stream=stream.duplicate()
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis: stream.loop=true
	elif stream is AudioStreamWAV:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_end=int(stream.get_length()*stream.mix_rate)
	return stream

func _tune() -> void:
	player.stop()
	live.stop()
	if station<3:
		live.tune(player,STATIONS[station][1],enabled)
	else:
		_playlist.clear()
		for file in DirAccess.get_files_at("user://radio/"):
			if file.get_extension().to_lower() in ["mp3","ogg","wav"]:_playlist.append("user://radio/"+file)
		_playlist.sort();_track=0
		_play_local()
	_message_left=4
	_save()

func _play_local() -> void:
	if _playlist.is_empty():player.stream=null;return
	var path:=_playlist[_track]
	if path.ends_with(".mp3"):player.stream=AudioStreamMP3.load_from_file(path)
	elif path.ends_with(".ogg"):player.stream=AudioStreamOggVorbis.load_from_file(path)
	else:player.stream=AudioStreamWAV.load_from_file(path)
	if enabled and player.stream:player.play()

func _next_track() -> void:
	if station==3 and not _playlist.is_empty():_track=(_track+1)%_playlist.size();_play_local()

func _save() -> void:
	GameSettings.set_option("emisora",station)
	GameSettings.set_option("radio_encendida",enabled)
	GameSettings.set_option("radio_volumen",volume)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_B:
			enabled=not enabled
			_tune()
		KEY_N:
			station=(station+1)%STATIONS.size()
			enabled=true
			_tune()
		KEY_COMMA:
			volume=maxf(0,volume-.1)
			_save()
		KEY_PERIOD:
			volume=minf(1,volume+.1)
			_save()
		_: return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if player==null: return
	_duck_left=maxf(0,_duck_left-delta)
	_message_left=maxf(0,_message_left-delta)
	var target:=linear_to_db(maxf(.0001,volume*(.10 if _duck_left>0 else .35)))
	player.volume_db=lerpf(player.volume_db,target,1-exp(-delta*5))
	label.text=("%s · %.0f %%\nB: radio  N: emisora  , / .: volumen"%[STATIONS[station][0],volume*100]) if enabled else "B: encender radio · H: bocina"
	if enabled:
		if station<3:label.text+=" · "+live.status
		elif _playlist.is_empty():label.text+=" · Añade tus canciones a la carpeta de radio"
		else:label.text+=" · "+_playlist[_track].get_file().get_basename()
	label.modulate.a=1.0 if enabled or _message_left>0 else .6
	if moto and world:
		var near_town:=false
		for town in world.get_town_centers():
			if town.distance_to(moto.global_position)<120: near_town=true
		ambience.volume_db=lerpf(ambience.volume_db,-44 if near_town else -33,delta)
