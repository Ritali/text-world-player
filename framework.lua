-- Layer to create quests and act as middle-man between Evennia and Agent
require 'utils'
local underscore = require 'underscore'
local DEBUG = false

local DEFAULT_REWARD = -0.1
local STEP_COUNT = 0 -- count the number of steps in current episode
local MAX_STEPS = 100

quests = {'You are hungry.','You are sleepy.', 'You are bored.', 'You are getting fat.'}
quest_actions = {'eat', 'sleep', 'watch' ,'exercise'} -- aligned to quests above
quest_checklist = {}
quest_levels = 1 --number of levels in any given quest
rooms = {'Living', 'Garden', 'Kitchen','Bedroom'}

actions = {"eat", "watch", "sleep", "exercise", "go"} -- hard code in
objects = {'north','south','east','west'} -- read from build file

symbols = {}
symbol_mapping = {}

NUM_ROOMS = 4


function random_teleport()
	local room_index = torch.random(1, NUM_ROOMS)
	data_out('@tel tut#0'..room_index)
	sleep(0.1)
	data_in()
	data_out('l')
	if DEBUG then
		print('Start Room : ' .. room_index ..' ' .. rooms[room_index])
	end
end

function random_quest()
	indxs = torch.randperm(#quests)
	for i=1,quest_levels do
		local quest_index = indxs[i]
		quest_checklist[#quest_checklist+1] = quest_index
	end
	if DEBUG then
		print("Start quest", quests[quest_checklist[1]], quest_actions[quest_checklist[1]])
	end
end

function login(user, password)
	local num_rooms = 4
	local pre_login_text = data_in()	
	print(pre_login_text)	
	sleep(1)
	data_out('connect ' .. user .. ' ' .. password)
end

--Function to parse the output of the game (to extract rewards, etc. )
function parse_game_output(text)
	-- extract REWARD if it exists
	-- text is a list of sentences
	local reward = nil
	local text_to_agent = {quests[quest_checklist[1]]}
	for i=1, #text do
		if i < #text  and string.match(text[i], '<EOM>') then
			text_to_agent = {quests[quest_checklist[1]]}
		elseif string.match(text[i], "REWARD") then
			if string.match(text[i], quest_actions[quest_checklist[1]]) then
				reward = tonumber(string.match(text[i], "%d+"))
			end
		else
			table.insert(text_to_agent, text[i])
		end
	end
	if not reward then
		reward = DEFAULT_REWARD
	end
	return text_to_agent, reward	
end

function getState(print_on)
	local terminal = (STEP_COUNT >= MAX_STEPS)
	local inData = data_in()
	while #inData == 0 or not string.match(inData[#inData],'<EOM>') do	
		TableConcat(inData, data_in())
	end
	local text, reward = parse_game_output(inData)		
	if DEBUG or print_on then
		print(text, reward)
		sleep(0.1)
		-- if reward > 0 then
		-- 	print(text, reward)
		-- 	sleep(2)
		-- end
	end
	if reward >= 1 then
		quest_checklist = underscore.rest(quest_checklist) --remove first element in table
		if #quest_checklist == 0 then
			--quest has been succesfully finished
			terminal = true
		end
	end

	local vector = convert_text_to_bow(text)
	return vector, reward, terminal
end

--take a step in the game
function step_game(action_index, object_index)
	data_out(build_command(actions[action_index], objects[object_index]))
	if DEBUG then 
		print(actions[action_index] .. ' ' .. objects[object_index])
	end
	STEP_COUNT = STEP_COUNT + 1
	return getState()
end


-- TODO
function nextRandomGame()
end

-- TODO
function newGame()
	random_teleport()
	random_quest()
	STEP_COUNT = 0
	return getState(false)
end

-- build game command to send to the game
function build_command(action, object)
	return action .. ' ' ..object
end


function parseLine( list_words, start_index)
	-- parse line to update symbols and symbol_mapping
	local sindx	
	for i=start_index,#list_words do			
		word = split(list_words[i], "%a+")[1]
		word = word:lower()	
		if symbol_mapping[word] == nil then
			sindx = #symbols + 1
			symbols[sindx] = word
			symbol_mapping[word] = sindx
		end
	end
end

-- read in text data from file with sentences (one sentence per line) - nicely tokenized
function makeSymbolMapping(filename)
	local file = io.open(filename, "r");
	local data = {}
	local parts
	for line in file:lines() do
		list_words = split(line, "%S+")
		if list_words[1] == '@detail' or list_words[1] == '@desc' then
			parseLine(list_words, 4)
		elseif list_words[1] == '@create/drop' then
			-- add to actionable objects			
			table.insert(objects, split(list_words[2], "%a+")[1])
		end
	end
end

function convert_text_to_bow(input_text)
	local vector = torch.zeros(#symbols)
	for i, line in pairs(input_text) do
		local list_words = split(line, "%a+")
		for i=1,#list_words do			
			local word = list_words[i]
			word = word:lower()
			--ignore words not in vocab
			if symbol_mapping[word] then	
				vector[symbol_mapping[word]] = vector[symbol_mapping[word]] + 1
			end
		end
	end
	return vector
end

function getActions()
	return actions
end

function getObjects()
	return objects
end

return {
	makeSymbolMapping = makeSymbolMapping,
	getActions = getActions, 
	getObjects = getObjects, 
	getState = getState, 
	step = step_game,
	newGame = newGame,
	nextRandomGame = nextRandomGame
}