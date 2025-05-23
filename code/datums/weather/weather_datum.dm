//The effects of weather occur across an entire z-level. For instance, lavaland has periodic ash storms that scorch most unprotected creatures.

GLOBAL_LIST_EMPTY(all_shelter_pods)

/datum/weather
	var/name = "space wind"
	var/desc = "Heavy gusts of wind blanket the area, periodically knocking down anyone caught in the open."

	var/telegraph_message = "<span class='warning'>The wind begins to pick up.</span>" //The message displayed in chat to foreshadow the weather's beginning
	var/telegraph_duration = 300 //In deciseconds, how long from the beginning of the telegraph until the weather begins
	var/telegraph_sound //The sound file played to everyone on an affected z-level
	var/telegraph_overlay //The overlay applied to all tiles on the z-level

	var/weather_message = "<span class='userdanger'>The wind begins to blow ferociously!</span>" //Displayed in chat once the weather begins in earnest
	var/weather_duration = 1200 //In deciseconds, how long the weather lasts once it begins
	var/weather_duration_lower = 1200 //See above - this is the lowest possible duration
	var/weather_duration_upper = 1500 //See above - this is the highest possible duration
	var/weather_sound
	var/weather_overlay
	var/weather_color = null

	var/end_message = "<span class='danger'>The wind relents its assault.</span>" //Displayed once the wather is over
	var/end_duration = 300 //In deciseconds, how long the "wind-down" graphic will appear before vanishing entirely
	var/end_sound
	var/end_overlay

	var/area_types = list(/area/space) //Types of area to affect
	var/list/impacted_areas = list() //Areas to be affected by the weather, calculated when the weather begins
	var/list/protected_areas = list()//Areas that are protected and excluded from the affected areas.
	var/impacted_z_levels // The list of z-levels that this weather is actively affecting

	var/overlay_layer = AREA_LAYER //Since it's above everything else, this is the layer used by default. TURF_LAYER is below mobs and walls if you need to use that.
	var/overlay_plane = AREA_PLANE
	var/custom_overlay // Do we want to give it a non-standard weather effect
	var/overlay_dir = NORTH
	var/aesthetic = FALSE //If the weather has no purpose other than looks
	var/immunity_type = "storm" //Used by mobs to prevent them from being affected by the weather

	var/stage = WEATHER_END_STAGE //The stage of the weather, from 1-4

	// These are read by the weather subsystem and used to determine when and where to run the weather.
	var/probability = 0 // Weight amongst other eligible weather. If zero, will never happen randomly.
	var/target_trait = STATION_LEVEL // The z-level trait to affect when run randomly or when not overridden.

	var/barometer_predictable = FALSE
	var/next_hit_time = 0 //For barometers to know when the next storm will hit

	var/area_act = FALSE // Does this affect more than just mobs, or the landscape?

	var/list/inside_areas = list() // Any areas not in the outside terf
	var/list/outside_areas = list() // Any areas listed as "outside"
	var/list/eligible_areas = list() // For variable playing or not playing sounds for shuttles

/datum/weather/New(z_levels)
	..()
	impacted_z_levels = z_levels
	RegisterSignal(SSdcs, COMSIG_GLOB_SHELTER_PLACED, PROC_REF(on_shelter_placed))

/datum/weather/proc/on_shelter_placed(datum/source, turf/center)
	SIGNAL_HANDLER // COMSIG_GLOB_SHELTER_PLACED
	GLOB.all_shelter_pods += center
	return

/datum/weather/proc/generate_area_list()
	var/list/affectareas = list()
	for(var/area_type in area_types)
		for(var/V in get_areas(area_type))
			affectareas += V
	for(var/V in protected_areas)
		affectareas -= get_areas(V)
	for(var/V in affectareas)
		var/area/A = V
		if(A.z in impacted_z_levels)
			impacted_areas |= A

/datum/weather/proc/telegraph()
	if(stage == WEATHER_STARTUP_STAGE)
		return
	stage = WEATHER_STARTUP_STAGE
	generate_area_list()
	weather_duration = rand(weather_duration_lower, weather_duration_upper)
	START_PROCESSING(SSweather, src)
	update_areas()
	update_eligible_areas()
	update_audio()
	for(var/M in GLOB.player_list)
		var/turf/mob_turf = get_turf(M)
		if(mob_turf && (mob_turf.z in impacted_z_levels))
			if(telegraph_message)
				to_chat(M, telegraph_message)
			if(telegraph_sound)
				SEND_SOUND(M, sound(telegraph_sound))

	addtimer(CALLBACK(src, PROC_REF(start)), telegraph_duration)

/datum/weather/proc/start()
	if(stage >= WEATHER_MAIN_STAGE)
		return
	stage = WEATHER_MAIN_STAGE
	update_areas()
	update_audio()
	for(var/M in GLOB.player_list)
		var/turf/mob_turf = get_turf(M)
		if(mob_turf && (mob_turf.z in impacted_z_levels))
			if(weather_message)
				to_chat(M, weather_message)
			if(weather_sound)
				SEND_SOUND(M, sound(weather_sound))
	addtimer(CALLBACK(src, PROC_REF(wind_down)), weather_duration)

/datum/weather/proc/wind_down()
	if(stage >= WEATHER_WIND_DOWN_STAGE)
		return
	stage = WEATHER_WIND_DOWN_STAGE
	update_areas()
	update_audio()
	for(var/M in GLOB.player_list)
		var/turf/mob_turf = get_turf(M)
		if(mob_turf && (mob_turf.z in impacted_z_levels))
			if(end_message)
				to_chat(M, end_message)
			if(end_sound)
				SEND_SOUND(M, sound(end_sound))
	addtimer(CALLBACK(src, PROC_REF(end)), end_duration)

/datum/weather/proc/end()
	if(stage == WEATHER_END_STAGE)
		return 1
	stage = WEATHER_END_STAGE
	STOP_PROCESSING(SSweather, src)
	update_areas()
	update_audio()

/datum/weather/proc/can_weather_act(mob/living/L) //Can this weather impact a mob?
	var/turf/mob_turf = get_turf(L)
	if(!istype(L) || !mob_turf)
		return FALSE
	if(mob_turf && !(mob_turf.z in impacted_z_levels))
		return FALSE
	if(immunity_type in L.weather_immunities)
		return FALSE
	if(!(get_area(L) in impacted_areas))
		return FALSE
	return TRUE

/datum/weather/proc/weather_act(mob/living/L) //What effect does this weather have on the hapless mob?
	return

/datum/weather/proc/update_areas()
	for(var/V in impacted_areas)
		var/area/N = V
		N.layer = overlay_layer
		N.plane = overlay_plane
		if(!custom_overlay)
			N.icon = 'icons/effects/weather_effects.dmi'
		else
			N.icon = custom_overlay
		if(overlay_dir)
			N.dir = overlay_dir
		N.invisibility = 0
		N.color = weather_color
		switch(stage)
			if(WEATHER_STARTUP_STAGE)
				N.icon_state = telegraph_overlay
			if(WEATHER_MAIN_STAGE)
				N.icon_state = weather_overlay
			if(WEATHER_WIND_DOWN_STAGE)
				N.icon_state = end_overlay
			if(WEATHER_END_STAGE)
				N.color = null
				N.icon_state = ""
				N.icon = 'icons/turf/areas.dmi'
				N.dir = NORTH
				N.layer = initial(N.layer)
				N.plane = initial(N.plane)
				N.set_opacity(FALSE)


/datum/weather/proc/update_eligible_areas()
	for(var/z in impacted_z_levels)
		for(var/area/A in GLOB.space_manager.areas_in_z["[z]"])
			eligible_areas |= A

	// Don't play storm audio to shuttles that are not at lavaland
	var/miningShuttleDocked = is_shuttle_docked("mining", "mining_away")
	if(!miningShuttleDocked)
		eligible_areas -= get_areas(/area/shuttle/mining)

	var/laborShuttleDocked = is_shuttle_docked("laborcamp", "laborcamp_away")
	if(!laborShuttleDocked)
		eligible_areas -= get_areas(/area/shuttle/siberia)

	var/golemShuttleOnPlanet = is_shuttle_docked("freegolem", "freegolem_lavaland")
	if(!golemShuttleOnPlanet)
		eligible_areas -= get_areas(/area/shuttle/freegolem)

	for(var/i in 1 to length(eligible_areas))
		var/area/place = eligible_areas[i]
		if(place.outdoors)
			outside_areas |= place
		else
			inside_areas |= place

/datum/weather/proc/is_shuttle_docked(shuttleId, dockId)
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle(shuttleId)
	return M && M.getDockedId() == dockId

/datum/weather/proc/area_act()
	return

/datum/weather/proc/update_audio()
	return
