extends Node3D
## Fussgaenger-Figur an der Fussgaengerampel (ped_crossing.gd steuert
## ihre Position). Dieselbe Schnittstelle wie pedestrian.gd, damit die
## KI-Autos sie in ihrer pedestrians-Liste abfragen koennen:
## global_position = aktueller Standort, on_road() = auf der Fahrbahn.

var walking := false         ## wird von ped_crossing waehrend der Querung gesetzt
var watchers: Array = []     ## Kompatibilitaet (pedestrian.gd-Feld)
const Z_ROAD := -60.0


func on_road() -> bool:
	return walking and absf(global_position.z - Z_ROAD) < 4.0


## traffic_car fragt _walking ab: "wartet am Bordstein" soll die KI
## hier NICHT zum Halten bringen — die Ampel regelt das, kein Vorrang.
var _walking := true
