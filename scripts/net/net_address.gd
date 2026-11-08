class_name NetAddress
extends RefCounted
## Validation for the Host/Join screens and local network info.

const DEFAULT_PORT := 7777
## Ports below 1024 need admin rights on most systems.
const MIN_PORT := 1024
const MAX_PORT := 65535


## "" if `text` is a usable host address (IPv4 like 192.168.1.20, or
## "localhost"), otherwise a short error for the player.
static func validate_address(text: String) -> String:
	var value := text.strip_edges()
	if value.is_empty():
		return "Enter the host's IP address."
	if value.to_lower() == "localhost":
		return ""
	var parts := value.split(".")
	if parts.size() != 4:
		return "An IP address has four numbers, like 192.168.1.20."
	for part in parts:
		if part.is_empty() or not part.is_valid_int() or part.length() > 3 or (part.length() > 1 and part.begins_with("0")):
			return "Each part of the IP address must be a number from 0 to 255."
		var number := part.to_int()
		if number < 0 or number > 255:
			return "Each part of the IP address must be a number from 0 to 255."
	if value == "0.0.0.0" or value == "255.255.255.255":
		return "That address can't be joined."
	return ""


## "" if `text` is a whole number in MIN_PORT..MAX_PORT, otherwise an error.
static func validate_port(text: String) -> String:
	var value := text.strip_edges()
	if value.is_empty():
		return "Enter a port number."
	if not value.is_valid_int() or value.begins_with("+") or value.begins_with("-"):
		return "The port must be a whole number."
	var number := value.to_int()
	if number < MIN_PORT or number > MAX_PORT:
		return "The port must be between %d and %d." % [MIN_PORT, MAX_PORT]
	return ""


## This computer's LAN IPv4 addresses (what friends on the same network join).
static func local_addresses() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		if is_private_ipv4(address) and not found.has(address):
			found.append(address)
	found.sort()
	return found


static func is_private_ipv4(address: String) -> bool:
	if validate_address(address) != "" or address == "localhost":
		return false
	var parts := address.split(".")
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
