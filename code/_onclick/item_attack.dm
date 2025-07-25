/**
  *This is the proc that handles the order of an item_attack.
  *The order of procs called is:
  *tool_act on the target. If it returns TRUE, the chain will be stopped.
  *pre_attack() on src. If this returns TRUE, the chain will be stopped.
  *attackby on the target. If it returns TRUE, the chain will be stopped.
  *and lastly
  *afterattack. The return value does not matter.
  */
/obj/item/proc/melee_attack_chain(mob/user, atom/target, params)
	if(user.check_arm_grabbed(user.active_hand_index))
		to_chat(user, span_notice("I can't move my arm!"))
		return
	if(!user.has_hand_for_held_index(user.active_hand_index, TRUE)) //we obviously have a hadn, but we need to check for fingers/prosthetics
		to_chat(user, span_warning("I can't move the fingers."))
		return
	if(!istype(src, /obj/item/grabbing))
		if(HAS_TRAIT(user, TRAIT_CHUNKYFINGERS))
			to_chat(user, span_warning("...What?"))
			return
	if(tool_behaviour && target.tool_act(user, src, tool_behaviour))
		return
	if(pre_attack(target, user, params))
		return
	if(target.attackby(src,user, params))
		return
	if(QDELETED(src) || QDELETED(target))
		attack_qdeleted(target, user, TRUE, params)
		return
	afterattack(target, user, TRUE, params)

// Called when the item is in the active hand, and clicked; alternately, there is an 'activate held object' verb or you can hit pagedown.
/obj/item/proc/attack_self(mob/user)
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_SELF, user) & COMPONENT_NO_INTERACT)
		return
	interact(user)

/obj/item/proc/pre_attack(atom/A, mob/living/user, params) //do stuff before attackby!
	if(SEND_SIGNAL(src, COMSIG_ITEM_PRE_ATTACK, A, user, params) & COMPONENT_NO_ATTACK)
		return TRUE
	return FALSE //return TRUE to avoid calling attackby after this proc does stuff

/atom/proc/pre_attack_right(atom/A, mob/living/user, params)
	return FALSE

// No comment
/atom/proc/attackby(obj/item/W, mob/user, params)
	if(user.used_intent.tranged)
		return FALSE
	if(SEND_SIGNAL(src, COMSIG_PARENT_ATTACKBY, W, user, params) & COMPONENT_NO_AFTERATTACK)
		return TRUE
	return FALSE

/obj/attackby(obj/item/I, mob/living/user, params)
	if(I.obj_flags_ignore)
		return I.attack_obj(src, user)
	else
		return ..() || ((obj_flags & CAN_BE_HIT) && I.attack_obj(src, user))

/turf/attackby(obj/item/I, mob/living/user, params)
	return ..() || (max_integrity && I.attack_turf(src, user))

/mob/living/attackby(obj/item/I, mob/living/user, params)
	if(..())
		return TRUE
	var/adf = user.used_intent.clickcd
	if(istype(user.rmb_intent, /datum/rmb_intent/aimed))
		adf = round(adf * CLICK_CD_MOD_AIMED)
	if(istype(user.rmb_intent, /datum/rmb_intent/swift))
		adf = max(round(adf * CLICK_CD_MOD_SWIFT), CLICK_CD_INTENTCAP)
	user.changeNext_move(adf)
	return I.attack(src, user)

/mob/living
	var/tempatarget = null
	var/pegleg = 0			//Handles check & slowdown for peglegs. Fuckin' bootleg, literally, but hey it at least works.
	var/construct = 0

/obj/item/proc/attack(mob/living/M, mob/living/user)
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK, M, user) & COMPONENT_ITEM_NO_ATTACK)
		return FALSE
	SEND_SIGNAL(user, COMSIG_MOB_ITEM_ATTACK, M, user)
	if(item_flags & NOBLUDGEON)
		return FALSE	

	if(force && HAS_TRAIT(user, TRAIT_PACIFISM))
		to_chat(user, span_warning("I don't want to harm other living beings!"))
		return

	M.lastattacker = user.real_name
	M.lastattackerckey = user.ckey
	if(M.mind)
		M.mind.attackedme[user.real_name] = world.time
	if(force)
		if(user.used_intent)
			if(!user.used_intent.noaa)
				playsound(get_turf(src), pick(swingsound), 100, FALSE, -1)
			if(user.used_intent.no_attack) //BYE!!!
				return
	else
		return

//	if(force)
//		user.emote("attackgrunt")
	var/datum/intent/cached_intent = user.used_intent
	if(user.used_intent.swingdelay)
		if(!user.used_intent.noaa && isnull(user.mind))
			if(get_dist(get_turf(user), get_turf(M)) <= user.used_intent.reach)
				user.do_attack_animation(M, user.used_intent.animname, user.used_intent.masteritem, used_intent = user.used_intent, simplified = TRUE)
		sleep(user.used_intent.swingdelay)
	if(user.a_intent != cached_intent)
		return
	if(QDELETED(src) || QDELETED(M))
		return
	if(!user.CanReach(M,src))
		return
	if(user.get_active_held_item() != src)
		return
	if(user.incapacitated())
		return
	if((M.mobility_flags & MOBILITY_STAND))
		if(M.checkmiss(user))
			if(!user.used_intent.swingdelay)
				if(get_dist(get_turf(user), get_turf(M)) <= user.used_intent.reach)
					user.do_attack_animation(M, user.used_intent.animname, used_item = src, used_intent = user.used_intent, simplified = TRUE)
			return
	var/rmb_stam_penalty = 0
	if(istype(user.rmb_intent, /datum/rmb_intent/strong))
		rmb_stam_penalty = EXTRA_STAMDRAIN_SWIFSTRONG
	if(istype(user.rmb_intent, /datum/rmb_intent/swift))
		if(user.used_intent.clickcd > CLICK_CD_INTENTCAP)	//If we're on Swift and our intent is not already at the cap by default, we consume extra stamina.
			rmb_stam_penalty = EXTRA_STAMDRAIN_SWIFSTRONG
	// Release drain on attacks besides unarmed attacks/grabs is 1, so it'll just be whatever the penalty is + 1.
	// Unarmed attacks are the only ones right now that have differing releasedrain, see unarmed attacks for their calc.
	user.stamina_add(user.used_intent.releasedrain + rmb_stam_penalty)
	var/bad_guard = FALSE
	//We have Guard / Clash active, and are hitting someone who doesn't. Cheesing a 'free' hit with a defensive buff is a no-no. You get punished.
	if(user.has_status_effect(/datum/status_effect/buff/clash) && !M.has_status_effect(/datum/status_effect/buff/clash))
		bad_guard = TRUE
	if(M.has_status_effect(/datum/status_effect/buff/clash) && M.get_active_held_item() && ishuman(M) && !bad_guard)
		var/mob/living/carbon/human/HM = M
		var/obj/item/IM = M.get_active_held_item()
		var/obj/item/IU 
		if(user.used_intent.masteritem)
			IU = user.used_intent.masteritem
		HM.process_clash(user, IM, IU)
		return
	if(bad_guard)
		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			H.bad_guard(span_suicide("I switched stances too quickly! It drains me!"), cheesy = TRUE)
	if(user.mob_biotypes & MOB_UNDEAD)
		if(M.has_status_effect(/datum/status_effect/buff/necras_vow))
			if(isnull(user.mind))
				user.adjust_fire_stacks(5)
				user.IgniteMob()
			else
				if(prob(30))
					to_chat(M, span_warning("The foul blessing of the Undermaiden hurts us!"))
			user.adjust_blurriness(3)
			user.adjustBruteLoss(5)
			user.apply_status_effect(/datum/status_effect/churned, M)
	if(M.checkdefense(user.used_intent, user))
		return



	if(user.zone_selected == BODY_ZONE_PRECISE_R_INHAND)
		var/offh = 0
		var/obj/item/W = M.held_items[1]
		if(W)
			if(!(M.mobility_flags & MOBILITY_STAND))
				M.throw_item(get_step(M,turn(M.dir, 90)), offhand = offh)
			else
				M.dropItemToGround(W)
			M.visible_message(span_notice("[user] disarms [M]!"), \
							span_boldwarning("I'm disarmed by [user]!"))
			return

	if(user.zone_selected == BODY_ZONE_PRECISE_L_INHAND)
		var/offh = 0
		var/obj/item/W = M.held_items[2]
		if(W)
			if(!(M.mobility_flags & MOBILITY_STAND))
				M.throw_item(get_step(M,turn(M.dir, 270)), offhand = offh)
			else
				M.dropItemToGround(W)
			M.visible_message(span_notice("[user] disarms [M]!"), \
							span_boldwarning("I'm disarmed by [user]!"))
			return

	if(M.attacked_by(src, user))
		if(user.used_intent == cached_intent)
			var/tempsound = user.used_intent.hitsound
			if(tempsound)
				playsound(M.loc,  tempsound, 100, FALSE, -1)
			else
				playsound(M.loc,  "nodmg", 100, FALSE, -1)

	log_combat(user, M, "attacked", src.name, "(INTENT: [uppertext(user.used_intent.name)]) (DAMTYPE: [uppertext(damtype)])")
	add_fingerprint(user)


//the equivalent of the standard version of attack() but for object targets.
/obj/item/proc/attack_obj(obj/O, mob/living/user)
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_OBJ, O, user) & COMPONENT_NO_ATTACK_OBJ)
		return
	if(item_flags & NOBLUDGEON)
		return
	if(O.attacked_by(src, user))
		user.do_attack_animation(O, simplified = TRUE)
		return TRUE

/obj/item/proc/attack_turf(turf/T, mob/living/user, multiplier)
	if(T.max_integrity)
		if(T.attacked_by(src, user, multiplier))
			user.do_attack_animation(T, simplified = TRUE)
			return TRUE

/atom/movable/proc/attacked_by()
	return FALSE


/proc/get_complex_damage(obj/item/I, mob/living/user, blade_dulling, turf/closed/mineral/T)
	var/dullfactor = 1
	if(!I?.force)
		return 0
	var/newforce = I.force_dynamic
	testing("startforce [newforce]")
	if(!istype(user))
		return newforce
	var/cont = FALSE
	var/used_str = user.STASTR
	if(iscarbon(user))
		var/mob/living/carbon/C = user
		if(C.domhand)
			used_str = C.get_str_arms(C.used_hand)
	if(istype(user.rmb_intent, /datum/rmb_intent/strong))
		used_str++
	if(istype(user.rmb_intent, /datum/rmb_intent/weak))
		used_str--
	if(used_str >= 11)
		var/strmod
		if(used_str > STRENGTH_SOFTCAP && !HAS_TRAIT(user, TRAIT_STRENGTH_UNCAPPED))
			strmod = ((STRENGTH_SOFTCAP - 10) * STRENGTH_MULT)
			var/strcappedmod = ((used_str - STRENGTH_SOFTCAP) * STRENGTH_CAPPEDMULT)
			strmod += strcappedmod
		else
			strmod = ((used_str - 10) * STRENGTH_MULT)
		newforce = newforce + (newforce * strmod)
	else if(used_str <= 9)
		newforce = newforce - (newforce * ((10 - used_str) * 0.1))

	if(I.minstr)
		var/effective = I.minstr
		if(I.wielded)
			effective = max(I.minstr / 2, 1)
		if(effective > user.STASTR)
			newforce = max(newforce*0.3, 1)
			if(prob(33))
				if(I.wielded)
					to_chat(user, span_info("I am too weak to wield this weapon properly with both hands."))
				else
					to_chat(user, span_info("I am too weak to wield this weapon properly with one hand."))

	switch(blade_dulling)
		if(DULLING_CUT) //wooden that can't be attacked by clubs (trees, bushes, grass)
			switch(user.used_intent.blade_class)
				if(BCLASS_CUT)
					var/mob/living/lumberjacker = user
					var/lumberskill = lumberjacker.get_skill_level(/datum/skill/labor/lumberjacking)
					if(!I.remove_bintegrity(1))
						dullfactor = 0.2
					else
						dullfactor = 0.45 + (lumberskill * 0.15)
						lumberjacker.mind.add_sleep_experience(/datum/skill/labor/lumberjacking, (lumberjacker.STAINT*0.2))
					cont = TRUE
				if(BCLASS_CHOP)
					var/mob/living/lumberjacker = user
					var/lumberskill = lumberjacker.get_skill_level(/datum/skill/labor/lumberjacking)
					if(!I.remove_bintegrity(1))
						dullfactor = 0.3
					else
						dullfactor = 1.0 + (lumberskill * 0.25)
						lumberjacker.mind.add_sleep_experience(/datum/skill/labor/lumberjacking, (lumberjacker.STAINT*0.2))
					cont = TRUE
			if(!cont)
				return 0
		if(DULLING_BASH) //stone/metal, can't be attacked by cutting
			switch(user.used_intent.blade_class)
				if(BCLASS_BLUNT)
					cont = TRUE
				if(BCLASS_SMASH)
					dullfactor = 1.5
					cont = TRUE
				if(BCLASS_PICK)
					dullfactor = 1.5
					cont = TRUE
			if(!cont)
				return 0
		if(DULLING_BASHCHOP) //structures that can be attacked by clubs also (doors fences etc)
			switch(user.used_intent.blade_class)
				if(BCLASS_CUT)
					if(!I.remove_bintegrity(1))
						dullfactor = 0.8
					cont = TRUE
				if(BCLASS_CHOP)
					if(!I.remove_bintegrity(1))
						dullfactor = 0.8
					else
						dullfactor = 1.5
					cont = TRUE
				if(BCLASS_SMASH)
					dullfactor = 1.5
					cont = TRUE
				if(BCLASS_BLUNT)
					cont = TRUE
				if(BCLASS_PICK)
					var/mob/living/miner = user
					var/mineskill = miner.get_skill_level(/datum/skill/labor/mining)
					dullfactor = 1.5 * (mineskill * 0.1)
					cont = TRUE
			if(!cont)
				return 0
		if(DULLING_PICK) //cannot deal damage if not a pick item. aka rock walls
			if(!(user.mobility_flags & MOBILITY_STAND))
				to_chat(user, span_warning("I need to stand up to get a proper swing."))
				return 0
			if(user.used_intent.blade_class != BCLASS_PICK)
				return 0
			var/mob/living/miner = user
			var/mineskill = miner.get_skill_level(/datum/skill/labor/mining)
			newforce = newforce * (8+(mineskill*1.5))
			shake_camera(user, 1, 1)
			miner.mind.add_sleep_experience(/datum/skill/labor/mining, (miner.STAINT*0.2))
		if(DULLING_SHAFT_CONJURED)
			dullfactor = 1.2
		if(DULLING_SHAFT_WOOD)	//Weak to cut / chop. No changes vs stab, resistant to blunt
			switch(user.used_intent.blade_class)
				if(BCLASS_CUT)
					if(!I.remove_bintegrity(1))
						dullfactor = 0.5
					else
						dullfactor = 1.3
				if(BCLASS_CHOP)
					if(!I.remove_bintegrity(1))
						dullfactor = 0.5
					else
						dullfactor = 1.5
				if(BCLASS_STAB)
					dullfactor = 1
				if(BCLASS_BLUNT)
					dullfactor = 0.7
				if(BCLASS_SMASH)
					dullfactor = 0.5
				if(BCLASS_PICK)
					dullfactor = 0.5
		if(DULLING_SHAFT_REINFORCED)	//Weak to stab. No changes vs blunt, resistant to cut / chop
			switch(user.used_intent.blade_class)
				if(BCLASS_CUT)
					if(!I.remove_bintegrity(1))
						dullfactor = 0
					else
						dullfactor = 0.5
				if(BCLASS_CHOP)
					if(!I.remove_bintegrity(1))
						dullfactor = 0
					else
						dullfactor = 0.7
				if(BCLASS_STAB)
					dullfactor = 1.5
				if(BCLASS_BLUNT)
					dullfactor = 1
				if(BCLASS_SMASH)
					dullfactor = 1
				if(BCLASS_PICK)
					dullfactor = 0.7
		if(DULLING_SHAFT_METAL)	//Very weak to blunt. No changes vs stab, highly resistant to cut / chop. Pick can actually damage it.
			switch(user.used_intent.blade_class)
				if(BCLASS_CUT)
					if(!I.remove_bintegrity(1))
						dullfactor = 0
					else
						dullfactor = 0.25
				if(BCLASS_CHOP)
					if(!I.remove_bintegrity(1))
						dullfactor = 0
					else
						dullfactor = 0.4
				if(BCLASS_STAB)
					dullfactor = 0.75
				if(BCLASS_BLUNT)
					dullfactor = 1.3
				if(BCLASS_SMASH)
					dullfactor = 1.5
				if(BCLASS_PICK)
					dullfactor = 1
		if(DULLING_SHAFT_GRAND)	//Resistant to all
			switch(user.used_intent.blade_class)
				if(BCLASS_CUT)
					if(!I.remove_bintegrity(1))
						dullfactor = 0
					else
						dullfactor = 0.5
				if(BCLASS_CHOP)
					if(!I.remove_bintegrity(1))
						dullfactor = 0
					else
						dullfactor = 0.5
				if(BCLASS_STAB)
					dullfactor = 0.5
				if(BCLASS_BLUNT)
					dullfactor = 0.5
				if(BCLASS_SMASH)
					dullfactor = 1
				if(BCLASS_PICK)
					dullfactor = 0.5
	var/newdam = (I.force_dynamic * user.used_intent.damfactor) - I.force_dynamic
	newforce = (newforce + newdam) * dullfactor
	if(user.used_intent.get_chargetime() && user.client?.chargedprog < 100)
		newforce = newforce * 0.5
	if(!(user.mobility_flags & MOBILITY_STAND))
		newforce *= 0.5
	newforce = round(newforce,1)
	newforce = max(newforce, 1)
	testing("endforce [newforce]")
	return newforce

/obj/attacked_by(obj/item/I, mob/living/user)
	user.changeNext_move(CLICK_CD_INTENTCAP)
	var/newforce = (get_complex_damage(I, user, blade_dulling) * I.demolition_mod)
	if(!newforce)
		testing("dam33")
		return 0
	if(newforce < damage_deflection)
		testing("dam44")
		return 0
	if(user.used_intent.no_attack)
		return 0
	log_combat(user, src, "attacked", I)
	var/verbu = "hits"
	verbu = pick(user.used_intent.attack_verb)
	if(newforce > 1)
		if(user.stamina_add(5))
			user.visible_message(span_danger("[user] [verbu] [src] with [I]!"))
		else
			user.visible_message(span_warning("[user] [verbu] [src] with [I]!"))
			newforce = 1
	else
		user.visible_message(span_warning("[user] [verbu] [src] with [I]!"))
	take_damage(newforce, I.damtype, I.d_type, 1)
	if(newforce > 1)
		I.take_damage(1, BRUTE, I.d_type)
	return TRUE

/turf/proc/attacked_by(obj/item/I, mob/living/user, multiplier)
	var/newforce = get_complex_damage(I, user, blade_dulling)
	if(!newforce)
		testing("attack6")
		return 0
	if(newforce < damage_deflection)
		testing("attack7")
		return 0
	if(user.used_intent.no_attack)
		return 0
	user.changeNext_move(CLICK_CD_INTENTCAP)
	log_combat(user, src, "attacked", I)
	var/verbu = "hits"
	verbu = pick(user.used_intent.attack_verb)
	if(newforce > 1)
		if(user.stamina_add(5))
			user.visible_message(span_danger("[user] [verbu] [src] with [I]!"))
		else
			user.visible_message(span_warning("[user] [verbu] [src] with [I]!"))
			newforce = 1
	else
		user.visible_message(span_warning("[user] [verbu] [src] with [I]!"))

	if(multiplier)
		newforce = newforce * multiplier
	
	take_damage(newforce, I.damtype, I.d_type, 1)
	if(newforce > 1)
		I.take_damage(1, BRUTE, I.d_type)
	return TRUE

/mob/living/proc/simple_limb_hit(zone)
	if(!zone)
		return ""
	switch(zone)
		if(BODY_ZONE_HEAD)
			return "body"
		if(BODY_ZONE_CHEST)
			return "body"
		if(BODY_ZONE_R_LEG)
			return "body"
		if(BODY_ZONE_L_LEG)
			return "body"
		if(BODY_ZONE_R_ARM)
			return "body"
		if(BODY_ZONE_L_ARM)
			return "body"
		if(BODY_ZONE_PRECISE_R_EYE)
			return "body"
		if(BODY_ZONE_PRECISE_L_EYE)
			return "body"
		if(BODY_ZONE_PRECISE_NOSE)
			return "body"
		if(BODY_ZONE_PRECISE_MOUTH)
			return "body"
		if(BODY_ZONE_PRECISE_SKULL)
			return "body"
		if(BODY_ZONE_PRECISE_EARS)
			return "body"
		if(BODY_ZONE_PRECISE_NECK)
			return "body"
		if(BODY_ZONE_PRECISE_L_HAND)
			return "body"
		if(BODY_ZONE_PRECISE_R_HAND)
			return "body"
		if(BODY_ZONE_PRECISE_L_FOOT)
			return "body"
		if(BODY_ZONE_PRECISE_R_FOOT)
			return "body"
		if(BODY_ZONE_PRECISE_STOMACH)
			return "body"
		if(BODY_ZONE_PRECISE_GROIN)
			return "body"
		if(BODY_ZONE_PRECISE_R_INHAND)
			return "body"
		if(BODY_ZONE_PRECISE_L_INHAND)
			return "body"
	return "body"

/obj/item/proc/funny_attack_effects(mob/living/target, mob/living/user, nodmg)
	if(is_silver)
		if(world.time < src.last_used + 120)
			to_chat(user, span_notice("The silver effect is on cooldown."))
			return

		if(ishuman(target) && target.mind)
			var/mob/living/carbon/human/s_user = user
			var/mob/living/carbon/human/H = target
			var/datum/antagonist/werewolf/W = H.mind.has_antag_datum(/datum/antagonist/werewolf/)
			var/datum/antagonist/vampirelord/lesser/V = H.mind.has_antag_datum(/datum/antagonist/vampirelord/lesser)
			var/datum/antagonist/vampirelord/V_lord = H.mind.has_antag_datum(/datum/antagonist/vampirelord/)
			var/datum/antagonist/vampire/V_wretch = H.mind.has_antag_datum(/datum/antagonist/vampire)
			if(V_wretch && V_wretch.wretch_antag && !V_wretch.disguised)
				H.visible_message("<font color='white'>The silver weapon burns the vampire's flesh!</font>")
				to_chat(H, span_userdanger("The silver burns you!"))
				H.apply_status_effect(/datum/status_effect/debuff/silver_curse)
				src.last_used = world.time
			if(V)
				if(V.disguised)
					H.visible_message("<font color='white'>The silver weapon weakens the curse temporarily!</font>")
					to_chat(H, span_userdanger("I'm hit by my BANE!"))
					H.apply_status_effect(/datum/status_effect/debuff/silver_curse)
					src.last_used = world.time
				else
					H.visible_message("<font color='white'>The silver weapon weakens the curse temporarily!</font>")
					to_chat(H, span_userdanger("I'm hit by my BANE!"))
					H.apply_status_effect(/datum/status_effect/debuff/silver_curse)
					src.last_used = world.time
			if(V_lord)
				if(V_lord.vamplevel < 4 && !V)
					H.visible_message("<font color='white'>The silver weapon weakens the curse temporarily!</font>")
					to_chat(H, span_userdanger("I'm hit by my BANE!"))
					H.apply_status_effect(/datum/status_effect/debuff/silver_curse)
					src.last_used = world.time
				if(V_lord.vamplevel == 4 && !V)
					to_chat(s_user, "<font color='red'> The silver weapon fails!</font>")
					H.visible_message(H, span_userdanger("This feeble metal can't hurt me, I AM ANCIENT!"))
			if(W && W.transformed == TRUE)
				H.visible_message("<font color='white'>The silver weapon weakens the curse temporarily!</font>")
				to_chat(H, span_userdanger("I'm hit by my BANE!"))
				H.apply_status_effect(/datum/status_effect/debuff/silver_curse)
				src.last_used = world.time
	return

/mob/living/attacked_by(obj/item/I, mob/living/user)
	var/hitlim = simple_limb_hit(user.zone_selected)
	testing("[src] attacked_by")
	I.funny_attack_effects(src, user)
	if(I.force_dynamic)
		var/newforce = get_complex_damage(I, user)
		apply_damage(newforce, I.damtype, def_zone = hitlim)
		if(I.damtype == BRUTE)
			next_attack_msg.Cut()
			if(HAS_TRAIT(src, TRAIT_SIMPLE_WOUNDS))
				simple_woundcritroll(user.used_intent.blade_class, newforce, user, hitlim)
				/* No embedding on simple mobs, thank you!
				var/datum/wound/crit_wound  = simple_woundcritroll(user.used_intent.blade_class, newforce, user, hitlim)
				if(should_embed_weapon(crit_wound, I))
					// throw_alert("embeddedobject", /atom/movable/screen/alert/embeddedobject)
					simple_add_embedded_object(I, silent = FALSE, crit_message = TRUE)
					src.grabbedby(user, 1, item_override = I)
				*/
			var/haha = user.used_intent.blade_class
			if(newforce > 5)
				if(haha != BCLASS_BLUNT)
					I.add_mob_blood(src)
					var/turf/location = get_turf(src)
					add_splatter_floor(location)
					if(get_dist(user, src) <= 1)	//people with TK won't get smeared with blood
						user.add_mob_blood(src)
			if(newforce > 15)
				if(haha == BCLASS_BLUNT)
					I.add_mob_blood(src)
					var/turf/location = get_turf(src)
					add_splatter_floor(location)
					if(get_dist(user, src) <= 1)	//people with TK won't get smeared with blood
						user.add_mob_blood(src)
	send_item_attack_message(I, user, hitlim)
	if(I.force_dynamic)
		return TRUE

/mob/living/simple_animal/attacked_by(obj/item/I, mob/living/user)
	if(I.force_dynamic < force_threshold || I.damtype == STAMINA)
		playsound(loc, 'sound/blank.ogg', I.get_clamped_volume(), TRUE, -1)
	else
		return ..()

// Proximity_flag is 1 if this afterattack was called on something adjacent, in your square, or on your person.
// Click parameters is the params string from byond Click() code, see that documentation.
/obj/item/proc/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	SEND_SIGNAL(src, COMSIG_ITEM_AFTERATTACK, target, user, proximity_flag, click_parameters)
	SEND_SIGNAL(user, COMSIG_MOB_ITEM_AFTERATTACK, target, user, proximity_flag, click_parameters)
	if(force_dynamic && !user.used_intent.tranged && !user.used_intent.tshield)
		if(proximity_flag && isopenturf(target) && !user.used_intent?.noaa)
			var/adf = user.used_intent.clickcd
			if(istype(user.rmb_intent, /datum/rmb_intent/aimed))
				adf = round(adf * CLICK_CD_MOD_AIMED)
			if(istype(user.rmb_intent, /datum/rmb_intent/swift))
				adf = max(round(adf * CLICK_CD_MOD_SWIFT), CLICK_CD_INTENTCAP)
			user.changeNext_move(adf)
			playsound(get_turf(src), pick(swingsound), 100, FALSE, -1)
			user.aftermiss()
		if(!proximity_flag && ismob(target) && !user.used_intent?.noaa) //this block invokes miss cost clicking on seomone who isn't adjacent to you
			var/adf = user.used_intent.clickcd
			if(istype(user.rmb_intent, /datum/rmb_intent/aimed))
				adf = round(adf * CLICK_CD_MOD_AIMED)
			if(istype(user.rmb_intent, /datum/rmb_intent/swift))
				adf = max(round(adf * CLICK_CD_MOD_SWIFT), CLICK_CD_INTENTCAP)
			user.changeNext_move(adf)
			playsound(get_turf(src), pick(swingsound), 100, FALSE, -1)
			user.aftermiss()

// Called if the target gets deleted by our attack
/obj/item/proc/attack_qdeleted(atom/target, mob/user, proximity_flag, click_parameters)
	SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_QDELETED, target, user, proximity_flag, click_parameters)
	SEND_SIGNAL(user, COMSIG_MOB_ITEM_ATTACK_QDELETED, target, user, proximity_flag, click_parameters)

/obj/item/proc/get_clamped_volume()
	if(w_class)
		if(force_dynamic)
			return CLAMP((force_dynamic + w_class) * 4, 30, 100)// Add the item's force to its weight class and multiply by 4, then clamp the value between 30 and 100
		else
			return CLAMP(w_class * 6, 10, 100) // Multiply the item's weight class by 6, then clamp the value between 10 and 100

/mob/living/proc/send_item_attack_message(obj/item/I, mob/living/user, hit_area)
	var/message_verb = "attacked"
	if(user.used_intent)
		message_verb = "[pick(user.used_intent.attack_verb)]"
	else if(!I.force_dynamic)
		return
	var/message_hit_area = ""
	if(hit_area)
		message_hit_area = " in the [hit_area]"
	var/attack_message = "[src] is [message_verb][message_hit_area] with [I]!"
	var/attack_message_local = "I'm [message_verb][message_hit_area] with [I]!"
	if(user in viewers(src, null))
		attack_message = "[user] [message_verb] [src][message_hit_area] with [I]!"
		attack_message_local = "[user] [message_verb] me[message_hit_area] with [I]!"
	visible_message(span_danger("[attack_message][next_attack_msg.Join()]"),\
		span_danger("[attack_message_local][next_attack_msg.Join()]"), null, COMBAT_MESSAGE_RANGE)
	next_attack_msg.Cut()
	return 1
