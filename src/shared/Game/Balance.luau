--!strict

-- Baseline from docs/2026-10-09_core-loop_gd-spec.md, sections 11-12.
-- Field size is confirmed at 1200 x 1200; corn visibility still needs a Studio playtest.
return {
	target_round_min_sec = 420,
	target_round_max_sec = 600,
	hunt_start_delay_sec = 15,
	key_slot_count = 15,
	barrel_count = 3,
	max_catches = 2,
	stamina_capacity = 100,
	sprint_duration_sec = 4,
	stamina_refill_sec = 6,
	walk_speed = 12,
	sprint_speed = 18,
	monster_patrol_speed = 10,
	monster_chase_speed = 14,
	monster_detect_radius = 32,
	monster_lose_radius = 44,
	monster_lose_delay_sec = 1.5,
	monster_growl_radius = 72,
	monster_capture_radius = 3,
	capture_transition_sec = 1,
	respawn_protection_sec = 5,
	key_drop_adjust_radius = 6,
	interaction_radius = 4,
	escape_reward_diamonds = 10,
}
