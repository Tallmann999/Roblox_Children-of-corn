--!strict

-- Keep player-facing strings in the GD namespace; this slice has no hunt/stamina UI.
return table.freeze({
	corn_loop_title = "Дети кукурузы",
	corn_loop_start = "Начать",
	corn_loop_loading = "Подготовка раунда…",
	corn_loop_objective_search = "Найди ключ от ворот и сбеги",
	corn_loop_objective_return = "Ключ найден. Вернись к воротам",
	corn_loop_objective_exit = "Ворота открыты — беги наружу",
	corn_loop_need_key = "Нужен ключ",
	corn_loop_result_escape = "Ты сбежал",
	corn_loop_result_aborted = "Раунд завершён",
	corn_loop_reward = "+{count} алмазов",
	corn_loop_test_balance = "Алмазы в этом тесте: {count}",
	corn_loop_round_time = "Время раунда: {time}",
	corn_loop_retry = "Ещё раз",
	corn_loop_menu = "В меню",
	corn_loop_leave = "Завершить раунд",
	corn_loop_setup_error = "Не удалось подготовить раунд. Попробуй снова",
	corn_loop_connection_error = "Не удалось подключить интерфейс. Перезапусти тест Studio",
})
