extends RefCounted


static func write_result(result: Dictionary) -> void:
	var file := FileAccess.open("res://__verifier_result.json", FileAccess.WRITE)
	if file == null:
		push_error("Could not open res://__verifier_result.json for writing")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
