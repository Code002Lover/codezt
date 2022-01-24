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
local input_filename,output_filename
for i,v in pairs(args) do
  if(v == "-i") then
    input_filename = args[i+1]
  end
  if(v == "-o") then
    output_filename = args[i+1]
  end
end

assert(input_filename~=nil,"no input filename specified (hint: -i)")

local input_file = io.open(input_filename,"r")
local output_file = io.open(output_filename,"w+")

io.close(output_file)
output_file = io.open(output_filename,"a")
io.input(input_file)
io.output(output_file)

local stack  = {}
local last = 0
function push(t)
  assert(type(t)=="table" and #t==2,"compiler error when pushing")
  last = last + 1
  stack[last]=t
end
function pop()
  assert(last~=0,"no items to pop from stack")
  last = last - 1
  return stack[last+1]
end
function unsafe_pop()
  last = last - 1
  return stack[last+1] or {"nil","nil"}
end

function show_stack()
  info("number of elements on the stack:",last)
  if(last ~= 0) then
    info("elements on the stack:")
    for i=1,last do
      info("type:",stack[i][1],"value:",stack[i][2])
    end
  end
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


function run_line(line)
  for i=1,#line+1 do
    if(line[i] == " " or line[i]==nil or line[i]=="\n" or line[i]=="\t" or line[i]=="" or line[i]==";") then
      word = concat(collection)
      collection = {}
      if(values[word]) then
        word = values[word]
      end
      if(#collect_string ~= 0) then
        collect_string[#collect_string+1]=word
        if(sub(word,#word,#word) == '"' or word=='"' or word==' "') then
          p1 = concat(collect_string," ")
          push({"string",sub(p1,1,#p1-1)})
          collect_string = {}
        end
      end
      if(#collect~= 0) then
        if(word == "end") then end_expected = end_expected - 1 end
        if(word == "end" and (end_expected == -1 or collect[1]=="ignore-if" or (collect[1]=="repeat" and end_expected==0))) then
          --why doesn't repeat work in func
          if(collect[1]=="func") then
            table.remove(collect,1)--func
            functions[table.remove(collect,1)] = split(concat(collect," ")) --without funcname nor end
          end
          if(collect[1]=="repeat") then
            table.remove(collect,1)--repeat
            local code_to_run = split(concat(collect," "))
            collect = {}
            p2 = nil
            repeat
              run_line(code_to_run)
              p2 = pop() --{type,value}
              assert(p2[1]=="bool","top of the stack after a `repeat` must be of type boolean")
            until p2[2]~=true--why no fucking work
          end
          collect = {}
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
        end
      else
        if(word=="+") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and (p2[1]=="number" or p2[1]=="string"),"wrong type on stack: + : ")
          push({"number",(p1[1]=="number" and p2[1]=="number" and p1[2]+p2[2]) or p1[2]..p2[2]})
        elseif(word=="true") then
          push({"bool",true})
        elseif(word=="false") then
          push({"bool",false})
        elseif(sub(word,1,1)=='"' and sub(word,#word,#word) ~= '"') then
          collect_string = {sub(word,2,#word+1)}
        elseif(sub(word,1,1)=='"' and sub(word,#word,#word) == '"') then
            push({"string",sub(word,2,#word-1)})
        elseif(word=="httpget") then
          local body, code, headers, status = http.request(pop()[2])
          push({"string",status})
          push({"table",headers})
          push({"number",code})
          push({"string",body})
        elseif(word=="-") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: - : ")
          push({"number",p1[2]-p2[2]})
        elseif(word=="--") then
          p1 = pop()
          assert(p1[1]=="number","wrong type on stack: -- : ")
          push({"number",p1[2]-1})
        elseif(word=="++") then
          p1 = pop()
          assert(p1[1]=="number","wrong type on stack: ++ : ")
          push({"number",p1[2]+1})
        elseif(word=="rot") then
          p1 = pop()
          p2 = pop()
          p3 = pop()
          push(p2)
          push(p1)
          push(p3)
        elseif(word==">" or word=="gt") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: > : ")
          push({"bool",p1[2]>p2[2]})
        elseif(word=="<" or word=="lt") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: < : ")
          push({"bool",p1[2]<p2[2]})
        elseif(word==">>") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: >> : ")
          push({"number",rshift(p1[2],p2[2])})
        elseif(word=="<<") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: << : ")
          push({"number",lshift(p1[2],p2[2])})
        elseif(word=="*") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: * : ")
          push({"number",p1[2]*p2[2]})
        elseif(word=="/") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: / : ")
          push({"number",p1[2]/p2[2]})
        elseif(word=="%") then
          p1 = pop()
          p2 = pop()
          assert(p1[1]==p2[1] and p2[1]=="number","wrong type on stack: % : ")
          push({"number",p2[2]%p1[2]})
        elseif(word=="dup") then
          p1 = pop()
          push(p1)
          push(p1)
        elseif(word=="over") then
          p1 = pop()
          p2 = pop()
          push(p2)
          push(p1)
          push(p2)
        elseif(word=="2dup") then
          p1 = pop()
          p2 = pop()
          push(p2)
          push(p1)
          push(p2)
          push(p1)
        elseif(word=="drop") then
          pop()
        elseif(word=="print") then
          p1 = pop()
          print(p1[2])
        elseif(word=="cprint") then
          io.stdout:write(pop()[2],"\n")
        elseif(word=="==") then
          p1 = pop()
          p2 = pop()
          push({"bool",p1[2]==p2[2]})
        elseif(word=="!=" or word=="~=") then
          p1 = pop()
          p2 = pop()
          push({"bool",p1[2]~=p2[2]})
        elseif(word=="===") then
          p1 = pop()
          p2 = pop()
          push({"bool",p1[1]==p2[1] and p1[2]==p2[2]})
        elseif(word=="!==" or word=="~==") then
          p1 = pop()
          p2 = pop()
          push({"bool",not (p1[1]==p2[1] and p1[2]==p2[2])})
        elseif(word=="not" or word=="!") then
          p1 = pop()
          assert(p1[1] == "bool","'not' is only usable with type 'bool'")
          push({"bool",not p1[2]})
        elseif(word=="and" or word=="&&") then
          p1 = pop()
          p2 = pop()
          assert(p1[1] == "bool" and p2[1] == p1[1],"'not' is only usable with type 'bool'")
          push({"bool",p1[2]and p2[2]})
        elseif(word=="or") then
          p1 = pop()
          p2 = pop()
          assert(p1[1] == "bool" and p2[1] == p1[1],"'not' is only usable with type 'bool'")
          push({"bool",p1[2]or p2[2]})
        elseif(word=="!!") then
          show_stack()
        elseif(word=="switch") then
          p1 = pop()
          p2 = pop()
          push(p1)
          push(p2)
        elseif(word=="=") then
          set_value = true
        elseif(word=="set") then
          values[last_word]=pop()[2]
        elseif(word=="clear") then
          stack={}
          last=0
        elseif(word=="func" or word=="repeat") then
          collect = {word}
        elseif(word=="if") then
          p1 = pop()
          if(not (p1[2]==true and p1[1]=="bool")) then
            collect = {"ignore-if"}
          end
        elseif(word=="include" or word=="require" or word=="import") then
          p1 = pop()
          assert(p1[1]=="string","when including files, top of the stack must be a string")
          local included_file = io.open(p1[2],"r")
          run_file(included_file)
        elseif(word=="read") then
          push({"string",io.stdin:read()})
        elseif(word=="write") then
          io.stdout:write(pop()[2])
        elseif(sub(word,1,2)=="//" or word=="return") then
          break
        elseif(functions[sub(word,1,#word-2)]) then
          run_line(functions[sub(word,1,#word-2)])
        elseif(functions[word]) then
          error("function pointers are not implemented yet")
          --run_line(functions[word])
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
  if(last ~= 0) then
    warn("number of items on the stack must be 0 after full execution")
    warn("stack:")
    show_stack()
  end
end

local start = os.clock()
run_file(input_file)
info(os.clock()-start,"s to run the program")

io.close(input_file)

io.close(output_file)
