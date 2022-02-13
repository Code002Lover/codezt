local concat,sub = table.concat,string.sub

local tbl = {}
function split(str)
   tbl = {}
   for i=1,#str do
     tbl[#tbl+1] = sub(str,i,i)
   end
   return tbl
end

local err_ptr = error
local pri_ptr = print
local linecount = 0
local i = 0
function error(...)
  pri_ptr("[ERROR]",...)
  err_ptr("",1)
end
function info(...)
  pri_ptr("[INFO]",...)
end
function warn(...)
  pri_ptr("[WARN]",...)
end
function print(...)
  pri_ptr(...)
end

local args = arg
local input_filename = args[1]

assert(input_filename~=nil,"no input filename specified")

local input_file = io.open(input_filename,"r")
io.input(input_file)

local stack = {}
local lastelement = nil

function pop(position)
  return table.remove(stack, position or #stack)
end
unsafe_pop = pop

function push(str)
  stack[#stack+1] = str
end

local word_array = {}

word_array["+"] = function(word)
  p1 = pop()
  p2 = pop()
  push(concat({p2,word,p1}))
end
word_array["-"] = word_array["+"]
word_array["%"] = word_array["+"]
word_array["/"] = word_array["+"]
word_array["=="] = word_array["+"]
word_array["~="] = word_array["+"]
word_array["print"] = function(word)
  push(concat({word,"(",pop(),")"}))
end
word_array["debug"] = function()
  word_array["dup"]()
  word_array["print"]()
end
word_array["dup"] = function()
  p1 = pop()
  push(p1)
  push(p1)
end


local locals = {}
word_array["set"] = function()
  push(concat({last_word,"=",pop()}))
  locals[last_word]=true
end

word_array["clear"] = function()
  stack={}
end

word_array["drop"] = pop

word_array["on-stack"] = function()
  p1 = pop()
  index = #stack - tonumber(p1) --we want to get the element from the top of the stack, not the bottom
  push(pop(index))
end

word_array["over"] = function()
  p1 = pop()
  p2 = pop()
  push(p2)
  push(p1)
  push(p2)
end

word_array["2dup"] = function()
  p1 = pop()
  p2 = pop()
  push(p2)
  push(p1)
  push(p2)
  push(p1)
end

local line = ""
while line ~= nil do
  line = input_file:read("*line")
  if(line == nil)then break end --EOF

  line = split(line)
  words = {}
  collection = {}
  for i=1,#line+1 do
    if(line[i] == " " or line[i]==nil or line[i]=="\n" or line[i]=="\t" or line[i]=="" or line[i]==";") then
      words[#words+1]=concat(collection)
      collection = {}
    else
      collection[#collection+1]=line[i]
    end
  end
  for i=1,#words do
    word = words[i]
    info("encountered `"..word.."`")
    if(tonumber(word)~=nil) then
      push(word)
    elseif(word_array[word]~=nil) then
      word_array[word](word)
    elseif(locals[word]~=nil) then
      push(word)
      last_word = word
    else
      last_word = word
    end
  end
end
info("output:")
print("\n\n\n\n--output from czt to lua")
print(concat(stack, "\n"))
