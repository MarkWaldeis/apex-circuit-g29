extends SceneTree
## Diagnose: wie krumm ist die Mittellinie wirklich? Listet die engsten
## Stellen mit Index, Streckenposition und Radius, damit sich echte Haarnadeln
## von Messfehlern (Knicks in den Daten) unterscheiden lassen.

const RacingLine = preload("res://scripts/racing_line.gd")


func _initialize() -> void:
	var line = RacingLine.new()
	if not line.load_json("res://assets/track/racing_line.json"):
		quit(1)
		return
	var n: int = line.points.size()
	var tight: Array = []
	var corner_len := 0.0
	var total := 0.0
	var hist := [0, 0, 0, 0]
	for i in n:
		var k: float = absf(line.curvature_at(i, 6))
		var ds: float = line.s[(i + 1) % n] - line.s[i] if i + 1 < n else line.length - line.s[i]
		total += ds
		if k > 0.002:
			corner_len += ds
		if k > 0.05:
			hist[0] += 1
		elif k > 0.02:
			hist[1] += 1
		elif k > 0.01:
			hist[2] += 1
		else:
			hist[3] += 1
		tight.append({"i": i, "k": k, "s": line.s[i]})
	tight.sort_custom(func(a, b): return a["k"] > b["k"])
	print("CENTRE laps=%.1f m, Punkte mit |k|>0.002: %.1f m (%.0f%%)" % [
		total, corner_len, 100.0 * corner_len / maxf(total, 1.0)])
	print("CENTRE Verteilung: >0.05=%d, >0.02=%d, >0.01=%d, Rest=%d" % [
		hist[0], hist[1], hist[2], hist[3]])
	for j in 10:
		var t: Dictionary = tight[j]
		print("  eng s=%7.1f m  Index %4d  k=%.4f  R=%5.1f m" % [
			t["s"], t["i"], t["k"], 1.0 / maxf(t["k"], 1e-6)])
	# Der Verdacht: die engste Stelle liegt direkt vor dem Rundenanfang
	# (Index 1432 von 1440). Sieht der Punktvorrat dort wie ein Knick aus?
	for i in [1428, 1430, 1432, 1434, 1436, 1438, 0, 2, 4]:
		var p: Vector3 = line.points[wrapi(i, 0, n)]
		var t: Vector3 = line.flat_tangent(i)
		print("  Punkt %4d  pos=(%8.2f,%6.2f,%8.2f)  tangent=(%+.3f,%+.3f,%+.3f)  s=%.1f" % [
			i, p.x, p.y, p.z, t.x, t.y, t.z, line.s[wrapi(i, 0, n)]])
	print("  Abstand 1439->0: %.2f m" % line.points[1439].distance_to(line.points[0]))
	quit(0)
