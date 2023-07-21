//WARNING in order to port aquarium code you also need to port over signals_fish.dm
//and the entire fish folder since it heavily relies on those signals.
//There is also a small dependancy on LC13 sanity code but thats only on the admire proc.
#define AQUARIUM_LAYER_STEP 0.01
/// Aquarium content layer offsets
#define AQUARIUM_MIN_OFFSET 0.01
#define AQUARIUM_MAX_OFFSET 1

/obj/structure/aquarium
	name = "aquarium"
	desc = "Interacting with this structure with a empty hand allows you to admire it and restore sanity based on the quality of the creatures inside."
	density = TRUE
	anchored = TRUE

	icon = 'icons/obj/aquarium.dmi'
	icon_state = "aquarium_base"

	integrity_failure = 0.3

	var/fluid_type = AQUARIUM_FLUID_FRESHWATER
	var/fluid_temp = DEFAULT_AQUARIUM_TEMP
	var/min_fluid_temp = MIN_AQUARIUM_TEMP
	var/max_fluid_temp = MAX_AQUARIUM_TEMP

	/// Can fish reproduce in this quarium.
	var/allow_breeding = FALSE

	var/glass_icon_state = "aquarium_glass"
	var/broken_glass_icon_state = "aquarium_glass_broken"

	//This is the area where fish can swim
	var/aquarium_zone_min_px = 2
	var/aquarium_zone_max_px = 31
	var/aquarium_zone_min_py = 10
	var/aquarium_zone_max_py = 24

	var/list/fluid_types = list(AQUARIUM_FLUID_SALTWATER, AQUARIUM_FLUID_FRESHWATER, AQUARIUM_FLUID_SULPHWATEVER, AQUARIUM_FLUID_AIR)

	var/panel_open = TRUE

	///Current layers in use by aquarium contents
	var/list/used_layers = list()

	/// /obj/item/fish in the aquarium - does not include things with aquarium visuals that are not fish
	var/list/tracked_fish = list()

/obj/structure/aquarium/Initialize(mapload)
	. = ..()
	update_icon()
	RegisterSignal(src,COMSIG_PARENT_ATTACKBY, .proc/feed_feedback)

/obj/structure/aquarium/Entered(atom/movable/arrived, atom/old_loc, list/atom/old_locs)
	. = ..()
	if(istype(arrived,/obj/item/food/fish))
		tracked_fish += arrived

/obj/structure/aquarium/Exited(atom/movable/gone, direction)
	. = ..()
	tracked_fish -= gone

/obj/structure/aquarium/proc/request_layer(layer_type)
	/**
	 * base aq layer
	 * min_offset = this value is returned on bottom layer mode
	 * min_offset + 0.1 fish1
	 * min_offset + 0.2 fish2
	 * ... these layers are returned for auto layer mode and tracked by used_layers
	 * min_offset + max_offset = this value is returned for top layer mode
	 * min_offset + max_offset + 1 = this is used for glass overlay
	 */
	//optional todo: hook up sending surface changed on aquarium changing layers
	switch(layer_type)
		if(AQUARIUM_LAYER_MODE_BOTTOM)
			return layer + AQUARIUM_MIN_OFFSET
		if(AQUARIUM_LAYER_MODE_TOP)
			return layer + AQUARIUM_MAX_OFFSET
		if(AQUARIUM_LAYER_MODE_AUTO)
			var/chosen_layer = layer + AQUARIUM_MIN_OFFSET + AQUARIUM_LAYER_STEP
			while((chosen_layer in used_layers) && (chosen_layer <= layer + AQUARIUM_MAX_OFFSET))
				chosen_layer += AQUARIUM_LAYER_STEP
			used_layers += chosen_layer
			return chosen_layer

/obj/structure/aquarium/proc/free_layer(value)
	used_layers -= value

/obj/structure/aquarium/proc/get_surface_properties()
	. = list()
	.[AQUARIUM_PROPERTIES_PX_MIN] = aquarium_zone_min_px
	.[AQUARIUM_PROPERTIES_PX_MAX] = aquarium_zone_max_px
	.[AQUARIUM_PROPERTIES_PY_MIN] = aquarium_zone_min_py
	.[AQUARIUM_PROPERTIES_PY_MAX] = aquarium_zone_max_py

/obj/structure/aquarium/update_overlays()
	. = ..()
	if(panel_open)
		. += "panel"

	//Glass overlay goes on top of everything else.
	var/mutable_appearance/glass_overlay = mutable_appearance(icon,broken ? broken_glass_icon_state : glass_icon_state,layer=AQUARIUM_MAX_OFFSET-1)
	. += glass_overlay

/obj/structure/aquarium/examine(mob/user)
	. = ..()
	. += "<span class='notice'>Alt-click to [panel_open ? "close" : "open"] the control panel.</span>"

/obj/structure/aquarium/AltClick(mob/user)
	if(!isliving(user))
		return ..()
	panel_open = !panel_open
	update_icon()

/obj/structure/aquarium/wrench_act(mob/living/user, obj/item/I)
	if(default_unfasten_wrench(user,I))
		return TRUE

/obj/structure/aquarium/attackby(obj/item/I, mob/living/user, params)
	if(broken)
		var/obj/item/stack/sheet/glass/glass = I
		if(istype(glass))
			if(glass.get_amount() < 2)
				to_chat(user, "<span class='notice'>You need two glass sheets to fix the case!</span>")
				return
			to_chat(user, "<span class='notice'>You start fixing [src]...</span>")
			if(do_after(user, 2 SECONDS, target = src))
				glass.use(2)
				broken = FALSE
				obj_integrity = max_integrity
				update_icon()
			return TRUE
	else
		var/datum/component/aquarium_content/content_component = I.GetComponent(/datum/component/aquarium_content)
		if(content_component && content_component.is_ready_to_insert(src))
			if(user.transferItemToLoc(I,src))
				update_icon()
				return TRUE
		else
			return ..()
	return ..()

/obj/structure/aquarium/proc/feed_feedback(datum/source, obj/item/thing, mob/user, params)
	SIGNAL_HANDLER
	if(istype(thing, /obj/item/fish_feed))
		to_chat(user, "<span class='nicegreen'>You feed the fish.</span>")
	return NONE

/obj/structure/aquarium/interact(mob/user)
	if(!broken && user.pulling && isliving(user.pulling))
		var/mob/living/living_pulled = user.pulling
		var/datum/component/aquarium_content/content_component = living_pulled.GetComponent(/datum/component/aquarium_content)
		if(content_component && content_component.is_ready_to_insert(src))
			try_to_put_mob_in(user)
	else if(panel_open)
		. = ..() //call base ui_interact
	else
		admire(user)

/// Tries to put mob pulled by the user in the aquarium after a delay
/obj/structure/aquarium/proc/try_to_put_mob_in(mob/user)
	if(user.pulling && isliving(user.pulling))
		var/mob/living/living_pulled = user.pulling
		if(living_pulled.buckled || living_pulled.has_buckled_mobs())
			to_chat(user, "<span class='notice'>[living_pulled] is attached to something!</span>")
			return
		user.visible_message("<span class='notice'>[user] starts to put [living_pulled] into [src]!</span>")
		if(do_after(user, 10 SECONDS, target = src))
			if(QDELETED(living_pulled) || user.pulling != living_pulled || living_pulled.buckled || living_pulled.has_buckled_mobs())
				return
			var/datum/component/aquarium_content/content_component = living_pulled.GetComponent(/datum/component/aquarium_content)
			if(content_component || content_component.is_ready_to_insert(src))
				return
			user.visible_message("[user] stuffs [living_pulled] into [src]!")
			living_pulled.forceMove(src)
			update_icon()

///Apply sanity bonus depending on aquarium status
/obj/structure/aquarium/proc/admire(mob/living/user)
	to_chat(user,"<span class='notice'>You take a moment to watch [src].</span>")
	if(do_after(user, 5 SECONDS, target = src))
		if(ishuman(user))
			var/mob/living/carbon/human/L = user
			var/fish_points = 0
			for(var/obj/item/food/fish/fish in tracked_fish)
				var/this_fish_point = 0.5
				switch(fish.random_case_rarity)
					if(FISH_RARITY_RARE)
						this_fish_point = 1
					if(FISH_RARITY_VERY_RARE)
						this_fish_point = 2
					if(FISH_RARITY_GOOD_LUCK_FINDING_THIS)
						this_fish_point = 4
				if(fish.status == FISH_ALIVE)
					this_fish_point *= -1
				fish_points += this_fish_point
			L.adjustSanityLoss(fish_points)

/obj/structure/aquarium/ui_data(mob/user)
	. = ..()
	.["fluid_type"] = fluid_type
	.["temperature"] = fluid_temp
	.["allow_breeding"] = allow_breeding
	var/list/content_data = list()
	for(var/atom/movable/fish in contents)
		content_data += list(list("name"=fish.name,"ref"=ref(fish)))
	.["contents"] = content_data

/obj/structure/aquarium/ui_static_data(mob/user)
	. = ..()
	//I guess these should depend on the fluid so lava critters can get high or stuff below water freezing point but let's keep it simple for now.
	.["minTemperature"] = min_fluid_temp
	.["maxTemperature"] = max_fluid_temp
	.["fluidTypes"] = fluid_types

/obj/structure/aquarium/ui_act(action, params)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("temperature")
			var/temperature = params["temperature"]
			if(isnum(temperature))
				fluid_temp = clamp(temperature, min_fluid_temp, max_fluid_temp)
				. = TRUE
		if("fluid")
			if(params["fluid"] in fluid_types)
				fluid_type = params["fluid"]
				SEND_SIGNAL(src, COMSIG_AQUARIUM_FLUID_CHANGED, fluid_type)
				. = TRUE
		if("allow_breeding")
			allow_breeding = !allow_breeding
			. = TRUE
		if("remove")
			var/atom/movable/inside = locate(params["ref"]) in contents
			if(inside)
				if(isitem(inside))
					user.put_in_hands(inside)
				else
					inside.forceMove(get_turf(src))
				to_chat(user, "<span class='notice'>You take out [inside] from [src].</span>")

/obj/structure/aquarium/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Aquarium", name)
		ui.open()

/obj/structure/aquarium/obj_break(damage_flag)
	. = ..()
	if(!broken)
		aquarium_smash()

/obj/structure/aquarium/proc/aquarium_smash()
	broken = TRUE
	var/possible_destinations_for_fish = list()
	var/droploc = drop_location()
	if(isturf(droploc))
		possible_destinations_for_fish = get_adjacent_open_turfs(droploc)
	else
		possible_destinations_for_fish = list(droploc)
	playsound(src, 'sound/effects/glassbr3.ogg', 100, TRUE)
	for(var/atom/movable/fish in contents)
		fish.forceMove(pick(possible_destinations_for_fish))
	if(fluid_type != AQUARIUM_FLUID_AIR)
		var/datum/reagents/reagent_splash = new()
		reagent_splash.add_reagent(/datum/reagent/water, 30)
		chem_splash(droploc, 3, list(reagent_splash))
	update_icon()

#undef AQUARIUM_LAYER_STEP
#undef AQUARIUM_MIN_OFFSET
#undef AQUARIUM_MAX_OFFSET


/obj/structure/aquarium/prefilled/Initialize(mapload)
	. = ..()

	new /obj/item/aquarium_prop/rocks(src)
	new /obj/item/aquarium_prop/seaweed(src)

	new /obj/item/food/fish/goldfish(src)
	new /obj/item/food/fish/angelfish(src)
	new /obj/item/food/fish/guppy(src)
