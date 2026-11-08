class_name TrikeInputSource
extends Node
## Anything that fills a TrikeInput once per physics tick: the local keyboard
## (PlayerInputSource), an AI driver (AIDriver) or, later, the network.
## Trike and RiderController poll their `input_source` with the same call, so
## a racer's control can be swapped without either of them knowing.


func poll(_into: TrikeInput) -> void:
	pass
