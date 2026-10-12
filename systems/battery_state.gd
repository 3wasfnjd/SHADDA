class_name ShaddaBatteryState
extends RefCounted

enum State { DOCKED, GROUND, PLAYER, ROBOT, LOST }
const ALLOWED = {
	State.DOCKED: [State.PLAYER, State.ROBOT, State.GROUND],
	State.GROUND: [State.PLAYER, State.ROBOT, State.DOCKED],
	State.PLAYER: [State.GROUND, State.DOCKED],
	State.ROBOT: [State.PLAYER, State.GROUND, State.LOST],
	State.LOST: []
}
var state: State = State.DOCKED
var owner_id: int = -1
var dock_id: int = -1

func reset(slot: int) -> void:
	state = State.DOCKED
	owner_id = -1
	dock_id = slot

func transition(next: State, owner: int = -1, slot: int = -1) -> bool:
	if not next in ALLOWED[state]:
		return false
	if (next == State.PLAYER or next == State.ROBOT) and owner < 0:
		return false
	if next == State.DOCKED and slot < 0:
		return false
	state = next
	owner_id = owner if next in [State.PLAYER, State.ROBOT] else -1
	dock_id = slot if next == State.DOCKED else -1
	return true
