local concat,sub = table.concat,string.sub

local tbl = {}
local function split(str)
   tbl = {}
   for i=1,#str do
     tbl[#tbl+1] = sub(str,i,i)
   end
   return tbl
end

local pri_ptr = print
local linecount = 0
local function error(bool,...)
  io.stderr:write("[ERROR]\t",...,"\n")
  if(not bool) then
    os.exit(1)
  end
end
local function info(...)
  pri_ptr("[INFO]",...)
end
local function warn(...)
  pri_ptr("[WARN]",...)
end
local function print(...)
  pri_ptr(...)
end
local function assert(cond,msg)
  if(not cond) then
    error(false,msg)
  end
end

local args = arg
local input_filename = args[1]
local pop_on_replacing_set = args[2] == "true"
local ingore_unknown_end = args[3] == "true"
local ENABLE_HTTP = args[4] == "true"
--TODO: check args in a better way

assert(input_filename~=nil,"no input filename specified")
local input_file
if(input_filename~="dump_words") then
  input_file = io.open(input_filename,"r")
  io.input(input_file)
end

local types = {
  ["nil"          ] = true,
  ["number"       ] = true,
  ["bool"         ] = true,
  ["function_ptr" ] = true,
  ["string"       ] = true,
  ["table"        ] = true,
  ["char"         ] = true,
  ["file"         ] = true,
}

local stack  = {}
local last = 0
local function push(t)
  assert(type(t)=="table" and #t==2,"interpreter error when pushing")
  assert(types[t[1]]==true,"unknown type got pushed")
  last = last + 1
  stack[last]=t
end
local function pop(position)
  assert(last~=0,"no items to pop from stack")
  assert(position==nil or last >= position,"not enough items on the stack")
  last = last - 1
  if(position ~= nil) then
    return table.remove(stack, position)
  end
  return stack[last+1] or {"nil","nil"}
end
local function unsafe_pop()
  return (last~= 0 and pop()) or {"nil","nil"}
end

local function show_stack()
  local str = {""}
  str[#str+1] = concat({"number of elements on the stack:",last},"\t")

  if(last ~= 0) then
    str[#str+1] = "elements on the stack:"
    for j=1,last do
      str[#str+1] = concat({"type:",stack[j][1],"value:",tostring(stack[j][2])},"\t")
    end
  end
  print(concat(str,"\n[INFO]\t"))
end

local function BitXOR(a,b)--Bitwise xor
    local p,c=1,0
    while a>0 and b>0 do
        local ra,rb=a%2,b%2
        if ra~=rb then c=c+p end
        a,b,p=(a-ra)/2,(b-rb)/2,p*2
    end
    if a<b then a=b end
    while a>0 do
        local ra=a%2
        if ra>0 then c=c+p end
        a,p=(a-ra)/2,p*2
    end
    return c
end

local function StrXOR(a,b)
  local alen = #a
  local blen = #b
  local ret = {}
  local char = string.char
  for i=1,alen do
    ret[i]=a:byte(i)
    for j=1,blen do
      ret[i]=BitXOR(ret[i],b:byte(j))
    end
    ret[i] = char(ret[i])
  end
  return table.concat(ret)
end

local p1,p2,p3
local values = {}
local functions = {}
local set_value = false
local last_word = ""
local collect = {}
local end_expected = 0
local collect_string = {}
local http
if(ENABLE_HTTP) then
  http = require("socket.http")
end
local function lshift(x, by)
  return x * 2 ^ by
end
local function rshift(x, by)
  return math.floor(x / 2 ^ by)
end

local function checktype(tocheck,expected,word_error,custom_error)
  assert(tocheck~=nil and expected~=nil and word_error~=nil,"checktype expects arguments")
  if(type(tocheck)=="table") then
    return checktype(tocheck[1],expected,word_error,custom_error)
  end
  if(tocheck~=expected) then
    if(custom_error) then
      return error(false,word_error)
    end
    error(false,concat({"`",word_error,"` expects type `",expected,"` but got type `",tocheck,"`"}))
  end
end

local function handle_string(str)
  if(str == nil or tostring(str) == "nil") then
    push({"nil","nil"})
    return
  end
  str = tostring(string.gsub(str,"\\n","\n"))
  str = tostring(string.gsub(str,"\\t","\t"))
  str = tostring(string.gsub(str,"\\r","\r"))
  str = tostring(string.gsub(str,"\\a","\a"))
  str = tostring(string.gsub(str,"\\b","\b"))
  str = tostring(string.gsub(str,"\\v","\v"))
  if(#str == 1) then
    push({"char",str})
  else
    push({"string",str})
  end
end

local word_array = {}
local word
local collection

local function run_line(line)
  for i=1,#line+1 do
    if(line[i] == " " or line[i]==nil or line[i]=="\n" or line[i]=="\t" or line[i]=="" or line[i]==";") then
      word = concat(collection)
      collection = {}
      if(values[word]) then
        last_word = word
        word = values[word]
      end
      if(#collect_string ~= 0) then
        collect_string[#collect_string+1]=word
        if(sub(word,#word,#word) == '"' or word=='"' or word==' "') then
          p1 = concat(collect_string," ")
          handle_string(sub(p1,1,#p1-1))
          collect_string = {}
        end
      end
      if(#collect~=0) then
        if(word == "end") then
          end_expected = end_expected - 1
        end
        if(word == "end" and
            (
              (end_expected == -1 and collect[1] == "func") or
              (collect[1]=="ignore-if") or (collect[1]=="repeat" or collect[1]=="fourloop") or
              (collect[1]=="execute-if")
            )
        ) then
          if(collect[1]=="func") then
            table.remove(collect,1)--func
            p1 = table.remove(collect,1)
            info("creating function called",p1)
            functions[p1] = split(concat(collect," ")) --without funcname nor end
          end
          if(collect[1]=="fourloop") then
            table.remove(collect,1)--fourloop
            local code_to_run = split(concat(collect," "))
            collect = {}
            for _=1,4 do
              run_line(code_to_run)
            end
          end
          if(collect[1]=="execute-if") then
            table.remove(collect,1)--execute-if
            local code_to_run = split(concat(collect," "))
            collect = {}
            run_line(code_to_run)
          end
          if(collect[1]=="repeat") then
            table.remove(collect,1)--repeat
            local code_to_run = split(concat(collect," "))
            collect = {}
            p2 = nil
            repeat
              run_line(code_to_run)
              p2 = pop()
              checktype(p2,"bool","top of the stack after a `repeat` must be of type boolean",true)
            until p2[2]~=true
          end
          collect = {}
          end_expected = 0
        else
          if(word == "if" or word=="repeat" or word=="fourloop" or word=="if2" or word=="ifl") then
            end_expected = end_expected + 1
          end
          collect[#collect+1]=word
        end
        word = {}
      elseif(tonumber(word)~=nil) then
        if(set_value) then
          values[last_word]=word
          set_value = false
        else
          push({"number",tonumber(word)})
        end
      else
        if(word_array[word])then
          word_array[word]()
        elseif(sub(word,1,1)=='"' and sub(word,#word,#word) ~= '"') then
          collect_string = {sub(word,2,#word+1)}
        elseif(sub(word,1,1)=='"' and sub(word,#word,#word) == '"') then
            handle_string(sub(word,2,#word-1))
        elseif(sub(word,1,2)=="//" or word=="return") then
          break
        elseif(functions[word]) then
          push({"function_ptr",word})
        elseif(functions[sub(word,1,#word-2)]) then
          run_line(functions[sub(word,1,#word-2)])
        else
          last_word = word
        end
      end
    else
      collection[#collection+1] = line[i]
    end
  end
end

local function run_file(file)
  local line = ""
  while line ~= nil do
    line = file:read("*line")
    linecount = linecount + 1
    if(line == nil)then break end --EOF

    line = split(line)
    collection = {}
    run_line(line)
  end
end
if(input_filename == "dump_words") then
  local t = {}
  for i,_ in pairs(word_array) do
    t[#t+1]=i
  end
  print(table.concat(t, "|"))
  return
end

local DEBUG_TYPE_INFO = false

word_array["toggle-debugging"] = function()
  DEBUG_TYPE_INFO = not DEBUG_TYPE_INFO
end

word_array["as"] = function()
  p1 = pop()
  p2 = pop()
  --p2 should also be known as p1 from now on
  functions[p1[2]] = functions[p2[2]]
end

word_array["^"] = function()
  p1 = pop()
  p2 = pop()
  if(p1[1]=="string" and p2[1]=="string") then
    push({"string",StrXOR(p2[2],p1[2])})
  else
    push({"number"},BitXOR(p2[2],p1[2]))
  end
end
word_array["xor"] = word_array["^"]

word_array["exit"] = function()
  p1 = pop()
  checktype(p1,"number","exit")
  os.exit(p1[2])
end

word_array["rot"] = function()
  push({"number",3})
  word_array["on-stack"]()
end

word_array["change-type"] = function()
  p1 = pop() --type to set to
  p2 = pop() --element to change
  checktype(p1,"string","change-type")
  p1 = p1[2] --for easier access to the string
  assert(types[p1]~=nil,"type to change to must be a valid type")
  assert(p1 ~= "table","cannot change to type 'table'")
  assert(p1 ~= "nil","cannot change to type 'nil'")
  assert(p2[1]~="nil","cannot change nil to another type")
  assert(p2[1]~="table","cannot change table to another type")
  if(p1 == "number") then
    assert(tonumber(p2[2]) ~= nil,"types are not compatible")
    p2[2] = tonumber(p2[2])
  end
  if(p1 == "string" or p1=="function_ptr") then
    p2[2] = tostring(p2[2])
  end
  if(p1 == "bool") then
    assert(p2[2] == "true" or p2[2] == "false","types are not compatible")
    p2[2] = p2[2]=="true" --shortcut to parse a string to a boolean
  end
  p2[1] = p1 --change internal type to match that of the value
  push(p2)
end

word_array["true"] = function()
  push({"bool",true})
end

word_array["false"] = function()
  push({"bool",false})
end

word_array["+"] = function()
  p1 = pop()
  p2 = pop()
  if(p1[1]=="number") then
    push({"number",p1[2]+p2[2]})
  else
    handle_string(p2[2]..p1[2])
  end
end

word_array["add"] = function()
  --p1 is table, p2 is value
  p1 = pop()
  p2 = pop()
  if((p1[1]=="number" or p1[1] == "string") and (p2[1]=="number" or p2[1] == "string")) then
    push(p1)
    push(p2)
    word_array["+"]()
    return
  end
  assert(p1[1]=="table" or p2[1]=="table","'add' can only be used with types: `number` `string` `table`")
  if(p1[1]=="table") then
    p1[2][#p1[2]+1] = p2
    push(p1)
    return
  end
  if(p2[1]=="table") then
    p2[2][#p2[2]+1] = p1
    push(p2)
    return
  end
end

word_array["remove"] = function()
  p1 = pop()
  checktype(p1,"table","remove")
  p2 = table.remove(p1[2], #p1[2])
  push(p1)
  push(p2)
end

word_array["{}"] = function()
  push({"table",{}})
end
word_array["[]"] = word_array["{}"]

word_array["--"] = function()
  p1 = pop()
  checktype(p1,"number","--")
  push({"number",p1[2]-1})
end

word_array["++"] = function()
  p1 = pop()
  checktype(p1,"number","++")
  push({"number",p1[2]+1})
end

word_array["-"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","-")
  checktype(p2,"number","-")
  push({"number",p2[2]-p1[2]})
end

word_array[">"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number",">")
  checktype(p2,"number",">")
  push({"bool",p2[2]>p1[2]})
end
word_array["gt"] = word_array[">"]

word_array["<"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","<")
  checktype(p2,"number","<")
  push({"bool",p2[2]<p1[2]})
end
word_array["lt"] = word_array["<"]

word_array["/"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","/")
  checktype(p2,"number","/")
  push({"number",p2[2]/p1[2]})
end

word_array["/*"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","/*")
  checktype(p2,"number","/*")
  push({"number",p2[2]*(1/p1[2])})
end
word_array["div"] = word_array["/*"]

word_array["%"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","%")
  checktype(p2,"number","%")
  push({"number",p2[2]%p1[2]})
end
word_array["%*"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","%*")
  checktype(p2,"number","%*")
  p3 = p2[2]*(1/p1[2])
  p3 = (p3 - math.floor(p3)) * p1[2]
  push({"number",p3})
end


word_array["*"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","*")
  checktype(p2,"number","*")
  push({"number",p2[2]*p1[2]})
end

word_array["<<"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","<<")
  checktype(p2,"number","<<")
  push({"number",lshift(p2[2],p1[2])})
end
word_array["lsf"] = word_array["<<"]

word_array[">>"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number",">>")
  checktype(p2,"number",">>")
  push({"number",rshift(p2[2],p1[2])})
end
word_array["rsf"] = word_array[">>"]

word_array["call"] = function()
  p1 = pop()
  checktype(p1,"function_ptr","call")
  run_line(functions[p1[2]])
end

word_array["end"] = function()
  if(ingore_unknown_end) then return end
  error(false,"unknown `end` found")
end

word_array["httpget"] = function()
  assert(ENABLE_HTTP,"http is disabled")
  local body, code, headers, status = http.request(pop()[2])
  push({"string",status})
  push({"table",headers})
  push({"number",code})
  push({"string",body})
end

word_array["drop"] = function()
  pop()
end

word_array["unsafe_drop"] = function()
  unsafe_pop()
end

local function tbl2str(tabl)
  local str = "{"
  for i=1,#tabl do
    if(tabl[i][1]=="table") then
      tabl[i] = {"string",tbl2str(tabl[i][2])} --the [2] is because of how its stored
    end
    str = concat({str,tabl[i][2],(#tabl ~= i and ",") or ("")})
  end
  str = concat({str,"}"})
  return str
end

word_array["print"] = function()
  p1 = pop()
  if(p1[1]=="table") then
    print(tbl2str(p1[2]))
  else
    if(DEBUG_TYPE_INFO) then
      info(p1[1])
    end
    print(p1[2])
  end
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

word_array["unsafe_dup"] = function()
  push(unsafe_pop())
  word_array["dup"]()
end

word_array["on-stack"] = function()
  p1 = pop()
  checktype(p1,"number","on-stack")
  local index = p1[2]
  index = #stack - index --we want to get the element from the top of the stack, not the bottom
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

word_array["=="] = function()
  p1 = pop()
  p2 = pop()
  push({"bool",p1[2]==p2[2]})
end

word_array["!="] = function()
  p1 = pop()
  p2 = pop()
  push({"bool",p1[2]~=p2[2]})
end
word_array["~="] = word_array["!="]

word_array["==="] = function()
  p1 = pop()
  p2 = pop()
  push({"bool",p1[1]==p2[1] and p1[2]==p2[2]})
end

word_array["!=="] = function()
  p1 = pop()
  p2 = pop()
  push({"bool",not (p1[1]==p2[1] and p1[2]==p2[2])})
end
word_array["~=="] = word_array["!=="]

word_array["not"] = function()
  p1 = pop()
  checktype(p1,"bool","not")
  push({"bool",not p1[2]})
end
word_array["!"] = word_array["not"]

word_array["null"] = function()
  push({"nil","nil"})
end
word_array["nil"] = word_array["null"]
word_array["undefined"] = word_array["null"]
word_array["nothing"] = word_array["null"]

word_array["and"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"bool","and")
  checktype(p2,"bool","and")
  push({"bool",p1[2]and p2[2]})
end
word_array["&&"] = word_array["and"]

word_array["error"] = function()
  error(true,pop()[2])
end

word_array["or"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"bool","or")
  checktype(p2,"bool","or")
  push({"bool",p1[2]or p2[2]})
end

word_array["!!"] = show_stack

word_array["switch"] = function()
  p1 = pop()
  p2 = unsafe_pop()
  if(p2[1] == "nil") then
    push(p1)
    return
  end
  push(p1)
  push(p2)
end

word_array["loadstring"] = function()
  p1 = pop()
  checktype(p1,"string","loadstring")
  run_line(split(p1[2]))
end
word_array["runstring"] = word_array["loadstring"]
word_array["executestring"] = word_array["loadstring"]
word_array["eval"] = word_array["loadstring"]

word_array["open_file"] = function()
  p1 = pop() --filepath
  p2 = unsafe_pop()--mode
  checktype(p1,"string","open_file")
  if(p2[1]=="nil") then
    p2 = {"char","r"}
  end
  checktype(p2,"char","open_file")
  push({"file",io.open(p1[2],p2[2])})
end

word_array["read_line"] = function()
  p1 = pop() --file
  checktype(p1,"file","read_line")
  handle_string(p1[2]:read("*line"))
end

word_array["write_file"] = function()
  p1 = pop() --file
  p2 = pop() --text
  checktype(p1,"file","write_file")
  checktype(p2,"string","write_file")
  p1[2]:write(p2[2])
end

word_array["set"] = function()
  p1 = pop()
  if(values[last_word] and pop_on_replacing_set) then
    pop()
  end
  values[last_word]=p1[2]
end

word_array["clear"] = function()
  stack={}
  last=0
end --idk why anyone would want to use this

word_array["func"] = function()
  collect = {"func"}
end

word_array["repeat"] = function()
  collect = {"repeat"}
end

word_array["fourloop"] = function()
  collect = {"fourloop"}
end

word_array["ifl"] = function()
  p1 = pop()
  checktype(p1,"bool","if-loop")
  if(p1[2]) then
    word_array["repeat"]()
  end
end

word_array["if"] = function()
  p1 = pop()
  checktype(p1,"bool","if")
  if(not p1[2]) then --ignore it if its false
    collect = {"ignore-if"}
  else
    collect = {"execute-if"}
  end
  --collect = (not(p1[2]==true) and {"ignore-if"}) or {} --?
end

word_array["include"] = function()
  p1 = pop()
  checktype(p1,"string","include")
  local included_file = io.open(p1[2],"r")
  run_file(included_file)
end
word_array["require"] = word_array["include"]
word_array["import"] = word_array["include"]

word_array["read"] = function()
  push({"string",io.stdin:read()})
end

word_array["write"] = function()
  io.stdout:write(pop()[2])
end

word_array["#std"] = function()
  push({"string","std.czt"})
  word_array["include"]()
end

word_array["type"] = function()
  push({"string",unsafe_pop()[1]})
end

word_array["tostring"] = function()
  push({"string","string"})
  word_array["change-type"]()
end

word_array["sqrt"] = function()
  p1 = pop()
  checktype(p1,"number","sqrt")
  push({"number"},math.pow(p1[2],0.5))
end

word_array["pow"] = function()
  p1 = pop()
  p2 = pop()
  checktype(p1,"number","pow")
  checktype(p2,"number","pow")
  push({"number"},math.pow(p2[2],p1[2]))
end

word_array["assert"] = function()
  p1 = pop()
  if(p1[2]~=true) then
    error(true,"assertion failed")
  end
end

local start = os.clock()
run_file(input_file)
if(last ~= 0) then
  warn("number of items on the stack must be 0 after full execution")
  warn("stack:")
  show_stack()
end --after all files ran (even imports)
info(os.clock()-start.."s to run the program")

io.close(input_file)
