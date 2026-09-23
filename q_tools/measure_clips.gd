extends SceneTree
## Замер фазы свинга руки в Mixamo-клипах при порогах 0.3/0.5/0.7 от пика
## угловой скорости. Результат: res://q_tools/measure_out.txt

func _initialize() -> void:
	var out := FileAccess.open("res://q_tools/measure_out.txt", FileAccess.WRITE)
	for clip_name in ["AT_LEFT", "AT_RIGHT"]:
		var scn := load("res://Assets/Mixamo/%s.fbx" % clip_name) as PackedScene
		if scn == null:
			out.store_line("MEASURE %s: FAIL load" % clip_name)
			continue
		var inst := scn.instantiate()
		var ap := inst.get_node("AnimationPlayer") as AnimationPlayer
		var anim := ap.get_animation(&"mixamo_com") if ap != null else null
		if anim == null:
			out.store_line("MEASURE %s: FAIL clip" % clip_name)
			inst.free()
			continue
		for bone in ["LeftHand", "RightHand"]:
			for ti in anim.get_track_count():
				var tp := str(anim.track_get_path(ti))
				if not tp.ends_with(bone):
					continue
				if anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
					continue
				var n := anim.track_get_key_count(ti)
				var vels: Array = []
				var max_vel := 0.0
				var prev_q := Quaternion()
				var prev_t := 0.0
				for ki in n:
					var t := anim.track_get_key_time(ti, ki)
					var q: Quaternion = anim.track_get_key_value(ti, ki)
					if ki > 0:
						var dot := absf(prev_q.dot(q))
						var ang := 2.0 * acos(clampf(dot, -1.0, 1.0))
						var vel := ang / maxf(t - prev_t, 0.0001)
						vels.append([t, vel])
						max_vel = maxf(max_vel, vel)
					prev_q = q
					prev_t = t
				for thr in [0.3, 0.5, 0.7]:
					var start := -1.0
					var end := -1.0
					for v in vels:
						if v[1] >= max_vel * thr:
							if start < 0.0:
								start = v[0]
							end = v[0]
					out.store_line("MEASURE thr=%.1f %s %s len=%.3f swing=%.3f..%.3f norm=(%.2f, %.2f) peak=%.1f" % [thr, clip_name, bone, anim.length, start, end, start / anim.length, end / anim.length, max_vel])
				break
		inst.free()
	out.close()
	quit(0)
