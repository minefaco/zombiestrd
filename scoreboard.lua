local storage = minetest.get_mod_storage()
zombie_score = {}

local prizes = {
		  {500, "default:mese", 1, "mese block"},
		  {1000, "default:diamondblock", 1, "diamond block"},
          {1500, "default:diamondblock", 2, "diamond block"},
}

-- load scoreboard
local function openlist()

	local load = storage:to_table()
	zombie_score = load.fields
	
	for count in pairs(zombie_score) do
	zombie_score[count] = tonumber(zombie_score[count])
	end
    
end

-- save scoreboard
function zb_savelist()

	storage:from_table({fields=zombie_score})
	
end -- poi.save()

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


local function sortscore()
    local fname = "size[5,6]"
    local count = 1

      for k,v in spairs(zombie_score, function(t,a,b) return t[b] < t[a] end) do
	  --minetest.chat_send_all(count.." >>> "..k.." , "..v)
	  fname = fname.."label[1,"..(count*0.3)..";"..count.." >>> "..k.." , "..v.."]"
	  count = count + 1
	  if count > 10 then break end
      end
  
    fname = fname.."button_exit[1.5,5;2,1;quit;Exit]"
    return fname
end

function check_prizes(user,number)
      local name = user:get_player_name()
      local inv = user:get_inventory()
      for i in ipairs(prizes) do
         local goal = prizes[i][1]
	 local nodename = prizes[i][2]
	 local howmuch = prizes[i][3]
	 local sayit = prizes[i][4]
	 
	    if zombie_score[name] + number == goal then
		  minetest.chat_send_player(name, core.colorize("#FF6700", "Congratulation: You killed your "..goal.."s zombies !! Keep up the good work. "..howmuch.." "..sayit.." have been added to your inv"))
		  inv:add_item("main", {name=nodename, count=howmuch})
	    end
      end
end

minetest.register_chatcommand("zombie_score", {
	params = "",
	description = "Shows the best zombie killer",
	privs = {interact = true},
	func = function(name)

	    local fname = sortscore()
	    if fname then
	      --minetest.chat_send_player(name, ">>> Highscore is :"..score[highscore].." by "..highscore)
	      minetest.show_formspec(name, "zombiestrd:the_killers", fname)
	    end

	end,
})

-- Go and get them :D

openlist()
