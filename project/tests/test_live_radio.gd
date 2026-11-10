extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var player:=AudioStreamPlayer.new();root.add_child(player)
	var receiver:=PeruLiveRadio.new();root.add_child(receiver)
	receiver.tune(player,GameRadio.STATIONS[0][1],true)
	var deadline:=Time.get_ticks_msec()+30000
	while receiver.received_frames<44100 or receiver.peak<.005:
		await create_timer(.10).timeout
		if Time.get_ticks_msec()>deadline:break
	var ok:=receiver.received_frames>=44100 and receiver.peak>.005
	print("RADIO_AUDIO_RESULT ",ok," frames=",receiver.received_frames," peak=",receiver.peak," status=",receiver.status)
	receiver.stop();receiver.queue_free();player.queue_free();await process_frame
	quit(0 if ok else 1)
