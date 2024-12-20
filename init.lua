dofile(minetest.get_modpath("zombiestrd") .. DIR_DELIM .. "scoreboard.lua")

local abr = minetest.get_mapgen_setting('active_block_range')
local nodename_water = minetest.registered_aliases.mapgen_water_source
local node_lava = nil

local zombiestrd = {}
--zombiestrd.spawn_rate = 0.4		-- less is more

local abs = math.abs
local pi = math.pi
local floor = math.floor
local random = math.random
local sqrt = math.sqrt
local max = math.max
local min = math.min
local pow = math.pow
local sign = math.sign

local time = os.time

local zombiestrd_spawn_chance = 0.6
local spawn_rate = 1 - max(min(minetest.settings:get('zombiestrd_spawn_chance') or zombiestrd_spawn_chance,1),0)
local spawn_reduction = minetest.settings:get('zombiestrd_spawn_reduction') or 0.4

local spawn_only_in_area = false
if minetest.settings:get_bool('zombiestrd.only_in_area') then
    spawn_only_in_area = true

    minetest.register_chatcommand("zombies_armageddon", {
	    params = "<true/false>",
	    description = "Set enable/disable zombies spawning everywhere.",
	    privs = {server = true},
        func = function(name, param)
            local command = param

            if command == "false" then
                spawn_only_in_area = true
                minetest.chat_send_player(name, ">>> Armageddon is disabled")
            else
                spawn_only_in_area = false
                minetest.chat_send_player(name, ">>> Armageddon is enabled")
            end
        end,
    })
end
local spawn_ghosts = false
if minetest.settings:get_bool('zombiestrd.spawn_ghosts') then
    spawn_ghosts = true
end

local function dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

-- find zombie's head center and radius
local function get_head(luaent)
	local pos = luaent.object:get_pos()
	local off = luaent.collisionbox[6]
	local y=pos.y+luaent.collisionbox[5]-off
	pos.y = y
	return pos, off
end

-- custom behaviour
-- makes them move in stimulus' general direction for limited time
local function hq_attracted(self,prty,tpos)
	local timer = time() + random(10,20)	-- zombie's attention span
	local func = function(self)
		if time() > timer then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			if vector.distance(pos,tpos) > 3 then
				mobkit.goto_next_waypoint(self,tpos)
			else
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

-- override built in behavior to increase idling time

function zombiestrd.hq_roam(self,prty)
	local func=function(self)
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local neighbor = random(8)

			local height, tpos, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
			if height and not liquidflag then mobkit.dumbstep(self,height,tpos,0.3,20) end
		end
	end
	mobkit.queue_high(self,func,prty)
end

local function alert(pos)
	objs = minetest.get_objects_inside_radius(pos,abr*16)
	for _,obj in ipairs(objs) do
		if not obj:is_player() then
			local luaent = obj:get_luaentity()
			if luaent and luaent.name == 'zombiestrd:zombie' then
				hq_attracted(luaent,10,pos)
			end
		end
	end
end


local function lava_dmg(self,dmg)
	node_lava = node_lava or minetest.registered_nodes[minetest.registered_aliases.mapgen_lava_source]
	if node_lava then
		local pos=self.object:get_pos()
		local box = self.object:get_properties().collisionbox
		local pos1={x=pos.x+box[1],y=pos.y+box[2],z=pos.z+box[3]}
		local pos2={x=pos.x+box[4],y=pos.y+box[5],z=pos.z+box[6]}
		local nodes=mobkit.get_nodes_in_area(pos1,pos2)
		if nodes[node_lava] then mobkit.hurt(self,dmg) end
	end
end

local function zombie_brain(self)
	-- vitals should be checked every step
	if mobkit.timer(self,1) then lava_dmg(self,6) end
	
	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)									-- cease all activity
		mobkit.hq_die(self)												-- kick the bucket
		
		-- workaround for models bottom y being -1. Makes them blink white sometimes, why?
		local props = self.object:get_properties()
		props.collisionbox[2] = props.collisionbox[1]
		self.object:set_properties({collisionbox=props.collisionbox})
		return
	end
	
	if mobkit.timer(self,1) then 			-- decision making needn't happen every engine step
		local prty = mobkit.get_queue_priority(self)
		
		if prty < 50 and self.isinliquid then
			mobkit.hq_liquid_recovery(self,50)
			return
		end
		
		local pos=self.object:get_pos()
		
		if prty < 20 then
			local plyr=mobkit.get_nearby_player(self)
			if plyr then
				local pos2 = plyr:get_pos()
				if prty < 10 then	-- zombie not alert
					if vector.distance(pos,pos2) < self.view_range/3 and											
					(not mobkit.is_there_yet2d(pos,minetest.yaw_to_dir(self.object:get_yaw()),pos2) or 
					vector.length(plyr:get_player_velocity()) > 3) then
						mobkit.make_sound(self,'misc')
						mobkit.hq_hunt(self,20,plyr)
						if random()<=0.5 then alert(pos) end
					end
				else
					if vector.distance(pos,pos2) < self.view_range then
						mobkit.make_sound(self,'misc')
						mobkit.hq_hunt(self,20,plyr)
						if random()<=0.5 then alert(pos) end
					end
				end
			end
		end
		
		if mobkit.is_queue_empty_high(self) then
			zombiestrd.hq_roam(self,0)
		end
	end
end

local function ghost_brain(self)
	-- vitals should be checked every step
	if mobkit.timer(self,1) then lava_dmg(self,6) end
	
	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)									-- cease all activity
		mobkit.hq_die(self)												-- kick the bucket
		
		-- workaround for models bottom y being -1. Makes them blink white sometimes, why?
		local props = self.object:get_properties()
		props.collisionbox[2] = props.collisionbox[1]
		self.object:set_properties({collisionbox=props.collisionbox})
		return
	end
	
	if mobkit.timer(self,1) then 			-- decision making needn't happen every engine step
		local prty = mobkit.get_queue_priority(self)
		
		if prty < 50 and self.isinliquid then
			mobkit.hq_liquid_recovery(self,50)
			return
		end
		
		local pos=self.object:get_pos()
		
		if prty < 20 then
			local plyr=mobkit.get_nearby_player(self)
			if plyr then
				local pos2 = plyr:get_pos()
				if prty < 5 then	-- ghost not alert
					if vector.distance(pos,pos2) < self.view_range/2 and											
					(not mobkit.is_there_yet2d(pos,minetest.yaw_to_dir(self.object:get_yaw()),pos2) or 
					vector.length(plyr:get_player_velocity()) > 3) then
						mobkit.make_sound(self,'misc')
						mobkit.hq_hunt(self,20,plyr)
						if random()<=0.5 then alert(pos) end
					end
				else
					if vector.distance(pos,pos2) < self.view_range then
						mobkit.make_sound(self,'misc')
						mobkit.hq_hunt(self,20,plyr)
						if random()<=0.5 then alert(pos) end
					end
				end
			end
		end
		
		if mobkit.is_queue_empty_high(self) then
			zombiestrd.hq_roam(self,0)
		end
	end
end

local function shark_brain(self)
	if mobkit.timer(self,1) then lava_dmg(self,6) end
	mobkit.vitals(self)
	
	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)
		mobkit.hq_die(self)
		return
	end
	
	if mobkit.timer(self,1) then
		local prty = mobkit.get_queue_priority(self)
		if prty < 20 then
			local target = mobkit.get_nearby_player(self)
			if target and mobkit.is_alive(target) and mobkit.is_in_deep(target) and target:get_attach() == nil then
				mobkit.clear_queue_high(self)
				mobkit.hq_aqua_attack(self,20,target,7)
			end
		end
	end
	if mobkit.is_queue_empty_high(self) then mobkit.hq_aqua_roam(self,10,5) end
end

minetest.register_node("zombiestrd:display_target", {
	tiles = {"zombiestrd_target.png"},
	use_texture_alpha = true,
	walkable = false,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-.55,-.55,-.55, .55,.55,.55},
		},
	},
	selection_box = {
		type = "regular",
	},
	paramtype = "light",
	groups = {dig_immediate = 3, not_in_creative_inventory = 1},
	drop = "",
})

minetest.register_entity("zombiestrd:target", {
	physical = false,
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "wielditem",
	-- wielditem seems to be scaled to 1.5 times original node size
	visual_size = {x = 0.67, y = 0.67},
	textures = {"zombiestrd:display_target"},
	timer = 0,
	glow = 10,

	on_step = function(self, dtime)

		self.timer = self.timer + dtime

		-- remove after set number of seconds
		if self.timer > 1 then
			self.object:remove()
		end
	end,
})

local function locate( table, value )
    for i = 1, #table do
        if table[i] == value then return true end
    end
    return false
end

local function check_is_inside_area(pos, table)
    if areas and spawn_only_in_area == true then
        local areasAtPos = areas:getAreasAtPos(pos)
        for id, area in pairs(areasAtPos) do
            --minetest.chat_send_all(dump(area.name))
            if locate( table, area.name ) then
                return true
            end
        end
        return false
    end
    return true
end

local function spawn_monsters(pos, yaw, chance, distance_multiplier, monster_name, areas)
    -- is the player inside the area?
    if check_is_inside_area(pos, areas) then

        local dir = vector.multiply(minetest.yaw_to_dir(yaw),distance_multiplier)
        local pos2 = vector.add(pos,dir)
        if pos2 == nil then return end
        --minetest.add_entity(pos2, "zombiestrd:target") --debug target
        pos2.y=pos2.y-5
        local height, liquidflag = mobkit.get_terrain_height(pos2,32)
        if height == nil then height = 0 end
        local position_at_terrain_height = {x=pos2.x,y=height-0.01,z=pos2.z}

        --force the spawn area be inside the area
        local is_zombie_spawn_area = check_is_inside_area(position_at_terrain_height, areas)
        if is_zombie_spawn_area then
            --if height and height >= 0 and
            local node_at_pos = mobkit.nodeatpos(position_at_terrain_height)
            if not node_at_pos then return end
            if node_at_pos.is_ground_content then

                local objs = minetest.get_objects_inside_radius(pos,abr*distance_multiplier+5)
                local wcnt=0
                local dcnt=0
                local mobname = monster_name --'zombiestrd:zombie' --myTable[ math.random( #myTable ) ]
                if liquidflag then		-- sharks
                    --[[
                    local spnode = mobkit.nodeatpos({x=pos2.x,y=height+0.01,z=pos2.z})
                    local spnode2 = mobkit.nodeatpos({x=pos2.x,y=height+1.01,z=pos2.z}) -- node above to make sure won't spawn in shallows
                    nodename_water = nodename_water or minetest.registered_aliases.mapgen_water_source
                    if spnode and spnode2 and spnode.name == nodename_water and spnode2.name == nodename_water then
	                    for _,obj in ipairs(objs) do
		                    if not obj:is_player() then
			                    local entity = obj:get_luaentity()
			                    if entity and entity.name=='zombiestrd:shark' then return end
		                    end
	                    end
                        mobname = 'zombiestrd:shark'
                    else
	                    return false
                    end
                    ]]--
                    return false
                elseif height >= -10 and height <= 120 then		--zombies
                    for _,obj in ipairs(objs) do				-- count mobs in abrange
	                    if not obj:is_player() then
		                    local entity = obj:get_luaentity()
		                    if entity and entity.name:find('zombiestrd:') then
			                    chance=chance + (1-chance)*spawn_reduction	-- chance reduced for every mob in range
		                    end
	                    end
                    end
                end
                if chance < random() then
                    pos2.y = height+1.01
                    objs = minetest.get_objects_inside_radius(pos2,abr*distance_multiplier-2)
                    --[[for _,obj in ipairs(objs) do				-- do not spawn if another player around
                        if obj:is_player() then return end
                    end]]--
                    local obj=minetest.add_entity(pos2,mobname)			-- ok spawn it already damnit
                    return true
                end
            end
        end --monsters_spwan_area
    end
    return false
end


-- spawning is too specific to be included in the api, this is an example.
-- a modder will want to refer to specific names according to games/mods they're using 
-- in order for mobs not to spawn on treetops, certain biomes etc.
local function spawnstep(dtime)

	for _,plyr in ipairs(minetest.get_connected_players()) do
		if random()<dtime*0.2 then	-- each player gets a spawn chance every 5s on average
			local vel = plyr:get_player_velocity()
			local spd = vector.length(vel)
			local chance = spawn_rate * 1/(spd*0.75+1)  -- chance is quadrupled for speed=4
			local yaw
			if spd > 1 then
				-- spawn in the front arc
				yaw = minetest.dir_to_yaw(vel) + random()*0.35 - 0.75
			else
				-- random yaw
				yaw = random()*pi*2 - pi
			end
			local pos = plyr:get_pos()
            local distance_multiplier = 10 --16
			--local dir = vector.multiply(minetest.yaw_to_dir(yaw),abr*distance_multiplier)

            local zb_area = {"cemetery","Cemetery","monsters","zbd"}
            local spawned = spawn_monsters(pos, yaw, chance, distance_multiplier, 'zombiestrd:zombie', zb_area)

            if spawned == false and spawn_ghosts == true then
                chance = spawn_rate * 1.3
                local ghost_area = {"cemetery","Cemetery","monsters","gtd"}
                spawned = spawn_monsters(pos, yaw, chance, distance_multiplier, 'zombiestrd:ghost', ghost_area)
            end

		end
	end
end


minetest.register_globalstep(spawnstep)
-- minetest.register_globalstep(function(dtime)
	-- local spos=mobkit.get_spawn_pos_abr(dtime,5,10,0.5,0.4)
	-- if spos then minetest.add_entity(spos,'zombiestrd:zombie') end
-- end)

minetest.register_on_punchnode(
	function(pos, node, puncher, pointed_thing)
		if random()<=0.1 then
			alert(pos)
		end
	end
)

local function add_score(name, points, table, prize_index, player)
    local key = "plyr_"..name
    if table[key] then
        table[key] = table[key] + points
        check_prizes(player, table[key], prize_index)
    else
        table[key] = points
    end
    savelist()
end

minetest.register_entity("zombiestrd:zombie",{
											-- common props
	physical = true,
	stepheight = 0.1,			
	collide_with_objects = true,
	collisionbox = {-0.25, -1, -0.25, 0.25, 0.75, 0.25},
	visual = "mesh",
	mesh = "zombie_normal.b3d",
	textures = {"mobs_zombie.png","mobs_zombi2.png"},
	visual_size = {x = 1, y = 1},
	static_save = true,
	timeout = 600,
	on_step = mobkit.stepfunc,	-- required
	on_activate = mobkit.actfunc,		-- required
	get_staticdata = mobkit.statfunc,
											-- api props
	springiness=0,
	buoyancy = 0.75,					-- portion of hitbox submerged
	max_speed = 3,
	jump_height = 1.26,
	view_range = 24,
	lung_capacity = 10, 		-- seconds
	max_hp = 14,
	attack={range=0.3,damage_groups={fleshy=7}},
	animation = {
		walk={range={x=41,y=101},speed=40,loop=true},
		stand={range={x=0,y=40},speed=1,loop=true},
	},
	
	sounds = {
		misc='zombie',
		attack='zombie_bite',
		warn = 'angrydog',
		headhit = 'splash_hit',
		bodyhit = 'body_hit',
		charge = 'zombie_charge',
		},
	armor_groups={immortal=100},
	brainfunc = zombie_brain,
	
	on_punch=function(self, puncher, time_from_last_punch, tool_caps, dir)
		if mobkit.is_alive(self) then
			
			-- head seeking
			if type(puncher)=='userdata' and puncher:is_player() then
                local name = puncher:get_player_name()
				local pp = puncher:get_pos()
				pp.y = pp.y + puncher:get_properties().eye_height	-- pp is now camera pos
				local pm, radius = get_head(self)
				local look_dir = puncher:get_look_dir()
				local head_dir = vector.subtract(pm,pp)
				local dot = dot(look_dir,head_dir)
				local p2 = {x=pp.x+look_dir.x*dot, y=pp.y+look_dir.y*dot, z=pp.z+look_dir.z*dot}
				if vector.distance(pp,pm) <=2 then		-- a way to decrease punch range without dependences
					if mobkit.isnear3d(pm,p2,radius*0.8) and
					time_from_last_punch >= tool_caps.full_punch_interval-0.01 and
					tool_caps.damage_groups.fleshy > 3 then			-- valid headshot
						mobkit.make_sound(self,'headhit')
--						self.object:set_hp(99)
						self.hp=0
                        --PONCTUATION
                        add_score(name, 1, zombie_score, "zombie", puncher)
                        --END PONCTUATION
					else
						mobkit.make_sound(self,'bodyhit')
						if random()<=0.3 then alert(pp) end
						if mobkit.get_queue_priority(self) < 10 then
							mobkit.make_sound(self,'misc')
							mobkit.hq_hunt(self,10,puncher)
						end
					end
					-- kickback
					local hvel = vector.multiply(look_dir,4)
					self.object:set_velocity({x=hvel.x,y=max(hvel.y,1),z=hvel.z})
				end
			else
				local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
				self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
			end

		end
	end

})

minetest.register_entity("zombiestrd:ghost",{
											-- common props
	physical = true,
	stepheight = 0.1,				--EVIL!
	collide_with_objects = false,
	collisionbox = {-0.25, -1, -0.25, 0.25, 0.75, 0.25},
	visual = "mesh",
	mesh = "zombie_normal.b3d",
	textures = {"mobs_npc_ghost.png","mobs_npc_ghost2.png"},
	visual_size = {x = 1, y = 1},
	static_save = true,
	makes_footstep_sound = false,
	on_step = mobkit.stepfunc,	-- required
	on_activate = mobkit.actfunc,		-- required
	get_staticdata = mobkit.statfunc,
											-- api props
	springiness=0,
	buoyancy = 0.75,					-- portion of hitbox submerged
	max_speed = 5,
	jump_height = 3,
	view_range = 30,
	lung_capacity = 200, 		-- seconds
	max_hp = 50,
	attack={range=0.5,damage_groups={fleshy=7}},
	animation = {
		walk={range={x=41,y=101},speed=40,loop=true},
		stand={range={x=0,y=40},speed=1,loop=true},
	},

	sounds = {
		misc='ghost',
		attack='ghost_laugh',
		warn = 'angrydog',
		headhit = 'splash_hit',
		bodyhit = 'ghost_hit',
		charge = 'ghost_charge',
		},
	armor_groups={immortal=100},
	brainfunc = zombie_brain,
	
	on_punch=function(self, puncher, time_from_last_punch, tool_caps, dir)
		if mobkit.is_alive(self) then
			
			-- head seeking
			if type(puncher)=='userdata' and puncher:is_player() then
                local name = puncher:get_player_name()
				local pp = puncher:get_pos()
				pp.y = pp.y + puncher:get_properties().eye_height	-- pp is now camera pos
				local pm, radius = get_head(self)
				local look_dir = puncher:get_look_dir()
				local head_dir = vector.subtract(pm,pp)
				local dot = dot(look_dir,head_dir)
				local p2 = {x=pp.x+look_dir.x*dot, y=pp.y+look_dir.y*dot, z=pp.z+look_dir.z*dot}
				if vector.distance(pp,pm) <=2 then		-- a way to decrease punch range without dependences
					if mobkit.isnear3d(pm,p2,radius*0.8) and
					time_from_last_punch >= tool_caps.full_punch_interval-0.01 and
					tool_caps.damage_groups.fleshy > 3 then			-- valid headshot
						mobkit.make_sound(self,'headhit')
--						self.object:set_hp(99)
						self.hp=0
                        --PONCTUATION
                        add_score(name, 1, ghost_score, "ghost", puncher)
                        --END PONCTUATION
					else
						mobkit.make_sound(self,'bodyhit')
                        if mobkit.is_alive(self) then
                            mobkit.hurt(self,tool_caps.damage_groups.fleshy or 1)
						    if random()<=0.3 then alert(pp) end
						    if mobkit.get_queue_priority(self) < 10 then
							    mobkit.make_sound(self,'misc')
							    mobkit.hq_hunt(self,10,puncher)
						    end
                            if self.hp<=0 then
                                --PONCTUATION
                                add_score(name, 1, ghost_score, "ghost", puncher)
                                --END PONCTUATION
                            end
                        end
					end
					-- kickback
					local hvel = vector.multiply(look_dir,4)
					self.object:set_velocity({x=hvel.x,y=max(hvel.y,1),z=hvel.z})
				end
			else
				local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
				self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
			end

		end
	end
})


--[[minetest.register_entity("zombiestrd:shark",{
											-- common props
	physical = true,
	stepheight = 0.1,				--EVIL!
	collide_with_objects = true,
	collisionbox = {-0.5, -0.3, -0.5, 0.5, 0.3, 0.5},
	visual = "mesh",
	mesh = "shark.b3d",
	textures = {"shark3tex.png"},
	visual_size = {x = 1.5, y = 1.5},
	static_save = true,
	makes_footstep_sound = true,
	on_step = mobkit.stepfunc,	-- required
	on_activate = mobkit.actfunc,		-- required
	get_staticdata = mobkit.statfunc,
											-- api props
	springiness=0,
	buoyancy = 0.98,					-- portion of hitbox submerged
	max_speed = 5,
	jump_height = 1.26,
	view_range = 24,
--	lung_capacity = 0, 		-- seconds
	max_hp = 20,
	timeout=600,
	attack={range=0.8,damage_groups={fleshy=7}},
	sounds = {
		attack='sharkattack',
		},
	animation = {
		def={range={x=1,y=59},speed=40,loop=true},	
		fast={range={x=1,y=59},speed=80,loop=true},
		back={range={x=15,y=1},speed=-15,loop=false},
		},
	
	brainfunc = shark_brain,
	
	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if mobkit.is_alive(self) then
			local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
			self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
			
			mobkit.hurt(self,tool_capabilities.damage_groups.fleshy or 1)

			if type(puncher)=='userdata' and puncher:is_player() then	-- if hit by a player
				mobkit.clear_queue_high(self)							-- abandon whatever they've been doing
				mobkit.hq_aqua_attack(self,20,puncher,6)				-- get revenge
			end
		end
	end,
})]]--

--[[
minetest.register_on_chat_message(
	function(name, message)
		if message == 'doit' then
			minetest.chat_send_all(dump(minetest.registered_aliases.mapgen_water_source))
		end
	end
)	--]]
