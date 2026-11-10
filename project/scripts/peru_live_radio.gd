class_name PeruLiveRadio
extends Node
## Decodificación de señales oficiales hacia un búfer PCM acotado, sin guardar canciones.
var url:=""
var status:=""
var received_frames:=0
var peak:=0.0
var _process_info: Dictionary={}
var _pending:=PackedByteArray()
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _elapsed:=0.0

static func decoder_path() -> String:
	var folder:=ProjectSettings.globalize_path("res://../tools/.radio_runtime/imageio_ffmpeg/binaries")
	if DirAccess.dir_exists_absolute(folder):
		for file in DirAccess.get_files_at(folder):
			if file.begins_with("ffmpeg") and file.ends_with(".exe"):return folder.path_join(file)
	var bundled:=ProjectSettings.globalize_path("res://bin/media/ffmpeg.exe")
	return bundled if FileAccess.file_exists(bundled) else ""

func tune(player: AudioStreamPlayer,address: String,enabled: bool) -> void:
	stop();url=address;_player=player
	var stream:=AudioStreamGenerator.new();stream.mix_rate=44100;stream.buffer_length=1.2;player.stream=stream
	if not enabled:status="Apagada";return
	var decoder:=decoder_path()
	if decoder.is_empty():status="Decodificador no disponible";return
	_process_info=OS.execute_with_pipe(decoder,PackedStringArray(["-hide_banner","-loglevel","error","-nostdin","-reconnect","1","-reconnect_streamed","1","-reconnect_delay_max","4","-i",url,"-vn","-f","s16le","-ar","44100","-ac","2","pipe:1"]),false)
	if _process_info.is_empty():status="Sin señal";return
	player.play();_playback=player.get_stream_playback() as AudioStreamGeneratorPlayback
	status="Conectando…";_elapsed=0;received_frames=0;peak=0

func stop() -> void:
	if not _process_info.is_empty():
		var pid:=int(_process_info.get("pid",-1))
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
		for key in ["stdio","stderr"]:
			var file:=_process_info.get(key) as FileAccess
			if file:file.close()
	_process_info={};_pending.clear();_playback=null

func _exit_tree() -> void:stop()

func _process(delta: float) -> void:
	if _process_info.is_empty() or _playback==null:return
	_elapsed+=delta
	var pipe: FileAccess=_process_info.stdio
	for i in 8:
		if _pending.size()>44100*4*2:break
		var data:=pipe.get_buffer(16384)
		if data.is_empty():break
		_pending.append_array(data)
	var frames:=mini(_pending.size()/4,_playback.get_frames_available())
	if frames>0:
		var output:=PackedVector2Array();output.resize(frames)
		for i in frames:
			output[i]=Vector2(float(_pending.decode_s16(i*4))/32768.0,float(_pending.decode_s16(i*4+2))/32768.0)
			peak=maxf(peak,maxf(absf(output[i].x),absf(output[i].y)))
		_playback.push_buffer(output);_pending=_pending.slice(frames*4);received_frames+=frames;status="En vivo"
	if received_frames==0 and _elapsed>20:status="Sin señal · revisando conexión"
	var errors: FileAccess=_process_info.stderr
	errors.get_buffer(4096)
