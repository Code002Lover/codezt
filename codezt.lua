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

assert(input_filename~=nil,"no input filename specified (hint: -i)")

local input_file = io.open(input_filename,"r")

io.input(input_file)

local types = {
  ["nil"          ] = true,
  ["number"       ] = true,
  ["bool"         ] = true,
  ["function_ptr" ] = true,
  ["string"       ] = true,
  ["table"        ] = true
}

local stack  = {}
local last = 0
function push(t)
  assert(type(t)=="table" and #t==2,"interpreter error when pushing")
  assert(types[t[1]]==true,"unknown type got pushed")
  last = last + 1
  stack[last]=t
end
function pop()
  assert(last~=0,"no items to pop from stack")
  last = last - 1
  return stack[last+1] or {"nil","nil"}
end
function unsafe_pop()
  return (last~= 0 and pop()) or {"nil","nil"}
end

function show_stack()
  local str = {""}
  str[#str+1] = concat({"number of elements on the stack:",last},"\t")

  if(last ~= 0) then
    str[#str+1] = "elements on the stack:"
    for i=1,last do
      str[#str+1] = concat({"type:",stack[i][1],"value:",tostring(stack[i][2])},"\t")
    end
  end
  print(concat(str,"\n[INFO]\t"))
end

local values = {}
local functions = {}
local while_loops = {}
local set_value = false
local last_word = ""
local collect = {}
local end_expected = 0
local collect_string = {}
local http = require("socket.http")
function lshift(x, by)
  return x * 2 ^ by
end
function rshift(x, by)
  return math.floor(x / 2 ^ by)
end

local word_array = {}

word_array["rot"] = function()
  p1 = pop()
  p2 = pop()
  p3 = pop()
  push(p2)
  push(p1)
  push(p3)
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
  push({"number",(p1[1]=="number" and p2[1]=="number" and p2[2]+p1[2]) or p2[2]..p1[2]}) --`..` could be changed to a table concat in order for better performance
end

word_array["--"] = function()
  p1 = pop()
  assert(p1[1]=="number","wrong type on stack: -- : ")
  push({"number",p1[2]-1})
end

word_array["++"] = function()
  p1 = pop()
  assert(p1[1]=="number","wrong type on stack: ++ : ")
  push({"number",p1[2]+1})
end

word_array["-"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: - : ")
  push({"number",p2[2]-p1[2]})
end

word_array[">"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: > : ")
  push({"bool",p2[2]>p1[2]})
end
word_array["gt"] = word_array[">"]

word_array["<"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: < : ")
  push({"bool",p2[2]<p1[2]})
end
word_array["lt"] = word_array["<"]

word_array["/"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: / : ")
  push({"number",p2[2]/p1[2]})
end

word_array["/*"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: /* : ")
  push({"number",p2[2]*(1/p1[2])})
end
word_array["div"] = word_array["/*"]

word_array["%"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: % : ")
  push({"number",p2[2]%p1[2]})
end

word_array["*"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: * : ")
  push({"number",p2[2]*p1[2]})
end

word_array["<<"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: << : ")
  push({"number",lshift(p2[2],p1[2])})
end
word_array["lsf"] = word_array["<<"]

word_array[">>"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: >> : ")
  push({"number",rshift(p2[2],p1[2])})
end
word_array["rsf"] = word_array[">>"]

word_array["call"] = function()
  p1 = pop()
  assert(p1[1]=="function_ptr","wrong type on stack: call : ")
  run_line(functions[p1[2]])
end

word_array["end"] = function()
  error("unknown `end` found")
end

word_array["httpget"] = function()
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

word_array["print"] = function()
  p1 = pop()
  print(p1[2])
end

word_array["debug"] = function()
  p1 = pop()
  print(p1[2])
  push(p1)
end

word_array["dup"] = function()
  p1 = pop()
  push(p1)
  push(p1)
end

word_array["unsafe_dup"] = function()
  p1 = unsafe_pop()
  push(p1)
  push(p1)
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
  assert(p1[1] == "bool","'not' is only usable with type 'bool'")
  push({"bool",not p1[2]})
end
word_array["!"] = word_array["not"]

word_array["null"] = function()
  push({"nil","nil"})
end
word_array["nil"] = word_array["null"]
word_array["undefined"] = word_array["null"]
word_array["nix"] = word_array["null"]
word_array["leer"] = word_array["null"]
word_array["zerotwonotfound"] = word_array["null"]
word_array["no"] = word_array["null"]
word_array["luft"] = word_array["null"]

word_array["and"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1] == "bool" and p2[1] == p1[1],"'not' is only usable with type 'bool'")
  push({"bool",p1[2]and p2[2]})
end
word_array["&&"] = word_array["and"]

word_array["or"] = function()
  p1 = pop()
  p2 = pop()
  assert(p1[1] == "bool" and p2[1] == p1[1],"'not' is only usable with type 'bool'")
  push({"bool",p1[2]or p2[2]})
end

word_array["!!"] = show_stack
--smirk

word_array["switch"] = function()
  p1 = pop()
  p2 = pop()
  push(p1)
  push(p2)
end

word_array["="] = function()
  set_value = true
end

word_array["set"] = function()
  p1 = pop()
  if(values[last_word]) then
    pop()
  end
  values[last_word]=p1[2]
end

word_array["clear"] = function()
  stack={}
  last=0
end

word_array["func"] = function()
  collect = {"func"}
end

word_array["repeat"] = function()
  collect = {"repeat"}
end

word_array["ifl"] = word_array["repeat"]

word_array["if"] = function()
  p1 = pop()
  -- if(not (p1[2]==true and p1[1]=="bool")) then
  --   collect = {"ignore-if"}
  -- end
  collect = (not(p1[2]==true and p1[1]=="bool") and {"ignore-if"}) or {}
end

word_array["include"] = function()
  p1 = pop()
  assert(p1[1]=="string","when including files, top of the stack must be a string")
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
  push({"string",tostring(unsafe_pop()[2])})
end

--[[



]]

function handle_string(str)
  str = tostring(string.gsub(str,"\\n","\n"))
  str = tostring(string.gsub(str,"\\t","\t"))
  push({"string",str})
end

function run_line(line)
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
          handle_string(sub(str,1,#str-1))
          collect_string = {}
        end
      end
      if(#collect~= 0) then
        if(word == "end") then end_expected = end_expected - 1 end
        if(word == "end" and ((end_expected == -1 and collect[1] == "func") or (collect[1]=="ignore-if") or (collect[1]=="repeat"))) then
          if(collect[1]=="func") then
            table.remove(collect,1)--func
            p1 = table.remove(collect,1)
            functions[p1] = split(concat(collect," ")) --without funcname nor end
          end
          if(collect[1]=="repeat") then
            table.remove(collect,1)--repeat
            local code_to_run = split(concat(collect," "))
            collect = {}
            p2 = nil
            repeat
              run_line(code_to_run)
              p2 = pop()
              assert(p2[1]=="bool","top of the stack after a `repeat` must be of type boolean")
            until p2[2]~=true
          end
          collect = {}
          end_expected = 0
        else
          if(word == "if" or word=="repeat") then
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
          --TODO: add support for huge numbers, or at least handle them as strings (BigNum)
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
        elseif(functions[sub(word,1,#word-2)]) then
          run_line(functions[sub(word,1,#word-2)])
        elseif(functions[word]) then
          push({"function_ptr",word})
        else
          last_word = word
        end
      end
    else
      collection[#collection+1] = line[i]
    end
  end
end



function run_file(file)
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

local start = os.clock()
run_file(input_file)
if(last ~= 0) then
  warn("number of items on the stack must be 0 after full execution")
  warn("stack:")
  show_stack()
end --after all files ran (even imports)
info(os.clock()-start,"s to run the program")

io.close(input_file)
