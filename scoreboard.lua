local storage = minetest.get_mod_storage()
score = {}
zombie_score = {}
ghost_score = {}

local prizes = {
            {250, "binoculars:binoculars", 1, "binoculars"},
            {500, "default:mese_crystal", 5, "mese crystal"},
            {750, "default:mese", 1, "mese block"},
            {1000, "default:steel_ingot", 18, "steel ingot"},
            {1250, "default:diamond", 5, "diamond"},
            {1500, "default:diamondblock", 1, "diamond block"},
            {1750, "default:diamondblock", 2, "diamond block"},
            {2000, "default:obsidian", 99, "obsidian"},
}

-- load scoreboard
local function openlist()

	local load = storage:to_table()
	score = load.fields

    --minetest.debug("score monsters: " .. dump(score))
    if score["zombie_score"] ~= nil then
        --minetest.debug("score zombie: " .. dump(score["zombie_score"]))
        zombie_score = loadstring("return " .. score["zombie_score"])()
	    for count in pairs(zombie_score) do
	        zombie_score[count] = tonumber(zombie_score[count])
	    end
    else
        zombie_score = {}
    end
    if score["ghost_score"] ~=  nil then
        ghost_score = loadstring("return " .. score["ghost_score"])()
	    for count in pairs(ghost_score) do
	        ghost_score[count] = tonumber(ghost_score[count])
	    end
    else
        ghost_score = {}
    end

end

-- save scoreboard
function savelist()

    score["zombie_score"] = serializeTable(zombie_score)
    score["ghost_score"] = serializeTable(ghost_score)
	storage:from_table({fields=score})
	--minetest.chat_send_all(dump(score))
end -- poi.save()

function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then tmp = tmp .. name .. " = " end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp =  tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end


function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end


local function sortscore(score_table)
    local fname = "size[5,6]"
    local count = 1

      for k,v in spairs(score_table, function(t,a,b) return t[b] < t[a] end) do
	  --minetest.chat_send_all(count.." >>> "..k.." , "..v)
	  fname = fname.."label[1,"..(count*0.3)..";"..count.." >>> "..k.." , "..v.."]"
	  count = count + 1
	  if count > 10 then break end
      end
  
    fname = fname.."button_exit[1.5,5;2,1;quit;Exit]"
    return fname
end

function check_prizes(user, points, monster_name)
    --check_prizes(puncher, zombie_score[name], "zombie")
    local name = user:get_player_name()
    local inv = user:get_inventory()
    for i in ipairs(prizes) do
        local goal = prizes[i][1]
        local nodename = prizes[i][2]
        local howmuch = prizes[i][3]
        local sayit = prizes[i][4]

        if points == goal then
            minetest.chat_send_player(name, core.colorize("#FF6700", "Congratulation: You killed your "..goal.."s "..monster_name.."s !! Keep up the good work. "..howmuch.." "..sayit.." have been added to your inv"))
            inv:add_item("main", {name=nodename, count=howmuch})
        end
    end
end

minetest.register_chatcommand("zombie_score", {
	params = "",
	description = "Shows the best zombie killer",
	privs = {interact = true},
	func = function(name)

	    local fname = sortscore(zombie_score)
	    if fname then
	      --minetest.chat_send_player(name, ">>> Highscore is :"..score[highscore].." by "..highscore)
	      minetest.show_formspec(name, "zombiestrd:the_killers", fname)
	    end

	end,
})

minetest.register_chatcommand("ghost_score", {
	params = "",
	description = "Shows the best ghost killer",
	privs = {interact = true},
	func = function(name)

	    local fname = sortscore(ghost_score)
	    if fname then
	      --minetest.chat_send_player(name, ">>> Highscore is :"..score[highscore].." by "..highscore)
	      minetest.show_formspec(name, "zombiestrd:the_killers", fname)
	    end

	end,
})

-- Go and get them :D

openlist()
