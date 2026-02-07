@tool
extends EditorPlugin

var http_server: TCPServer
var port: int = 6006

func _enter_tree() -> void:
	http_server = TCPServer.new()
	var err = http_server.listen(port, "127.0.0.1")
	if err == OK:
		print("[VoiceDucky] Context server listening on http://127.0.0.1:%d/context" % port)
	else:
		push_error("[VoiceDucky] Failed to start context server on port %d" % port)

func _exit_tree() -> void:
	if http_server:
		http_server.stop()
		print("[VoiceDucky] Context server stopped")

func _process(_delta: float) -> void:
	if not http_server or not http_server.is_listening():
		return
	
	if http_server.is_connection_available():
		var peer = http_server.take_connection()
		if peer:
			handle_request(peer)

func handle_request(peer: StreamPeerTCP) -> void:
	peer.set_no_delay(true)
	
	var request = peer.get_string(peer.get_available_bytes())
	if not request.begins_with("GET"):
		peer.disconnect_from_host()
		return
	
	var context = get_editor_context()
	var json = JSON.stringify(context)
	
	var response = "HTTP/1.1 200 OK\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Content-Length: %d\r\n" % json.length()
	response += "\r\n"
	response += json
	
	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()

func get_editor_context() -> Dictionary:
	var context := {}
	
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root:
		context["scene_name"] = scene_root.scene_file_path.get_file()
		context["root_type"] = scene_root.get_class()
		context["node_count"] = count_nodes(scene_root)
		context["scene_tree"] = get_tree_summary(scene_root, 3)
	else:
		context["scene_name"] = "none"
		context["root_type"] = "none"
		context["node_count"] = 0
	
	var selection = EditorInterface.get_selection()
	var selected = selection.get_selected_nodes()
	if selected.size() > 0:
		var node = selected[0]
		context["selected_node"] = node.name
		context["selected_type"] = node.get_class()
		context["selected_path"] = str(node.get_path())
		
		if node.get_script():
			var script: Script = node.get_script()
			context["selected_script"] = script.resource_path.get_file()
	else:
		context["selected_node"] = "none"
	
	var script_editor = EditorInterface.get_script_editor()
	var current_script = script_editor.get_current_script()
	if current_script:
		context["open_script"] = current_script.resource_path.get_file()
	
	return context

func count_nodes(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += count_nodes(child)
	return count

func get_tree_summary(node: Node, max_depth: int, depth: int = 0) -> Array:
	if depth >= max_depth:
		return []
	
	var result := []
	var entry = "%s (%s)" % [node.name, node.get_class()]
	result.append(entry)
	
	for child in node.get_children():
		var child_entries = get_tree_summary(child, max_depth, depth + 1)
		for e in child_entries:
			result.append("  " + e)
	
	return result
