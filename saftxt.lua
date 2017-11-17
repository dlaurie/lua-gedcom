-- Standalone SAF text format to GEDCOM converter
-- Usage:
--   lua gedcom/saftxt.lua NAME.saf
-- Writes the GEDCOM as NAME.ged

--[[ TODO  
- Ignore superfluous semicolons.
- Support for multiple marriages.
- More tests and better error message for wrong input.
--]]

-- Determination of gender, surname and parentage
-- Surname of a child, if not specified in CAPITAL LETTERS, is assumed to be 
-- that of the male parent.
-- Immediately after the name, there may be comma-separated information in 
-- braces, with the following meaning:
--  M   male (default)
--  F   female (essential only if she has a spouse)
--  xx  child from second marriage (xxx etc for later marriages)
-- Failing gender information, spouses are assumed to be of the opposite sex.
-- Failing parentage information, intelligent deductions are made from dates.

local saftxt = {_VERSION="0.2",INDI={},FAM={}}
local hdr = [[
0 HEAD
1 SOUR SAFtext-to-GEDCOM v.%s
]]

local sanitize -- replace multibyte UTF8 and blank-flanked ASCII symbols by
--   one-byte surrogates
local process  -- handle one line of SAF file
local shipout  -- recursively concatenate table
local values   -- list of values in a table, ignoring keys
local trim     -- remove leading and trailing blanks
local normalize  -- write surname with normal Dutch capitalization (i.e.
                 -- 'de', 'van', 'ten' etc not capitalized)
local endinput = "^%-%-%-%-"  -- line starting with four hyphens

main = function ()
  local indi = setmetatable({},saftxt.INDI)
  local fam = setmetatable({},saftxt.FAM)
  local input = sanitize(io.open(arg[1]):read"a")
  local outname = arg[1]:gsub("%.saf$",".ged")
  if outname == arg[1] then
    error("Input filename must end in '.saf'")
  end
  local outfile = io.open(outname,"w")
  local fullcode = ''
  for line in input:gmatch"[^\n]+" do if line:match"%S" then
    if line:match(endinput) then break end
    fullcode = process(fullcode,line,indi,fam)
  end end
  outfile:write(hdr:format(saftxt._VERSION)) 
  if #indi>0 then outfile:write(shipout(indi,"\n"),"\n") end
  if #fam>0 then outfile:write(shipout(fam,"\n"),"\n") end
  outfile:write"0 TRLR\n" 
  outfile:close()  
end

values = function(tbl)
  local t = {}
  for _,v in pairs(tbl) do t[#t+1] = v end
  return t
end

local Event, textpat, eventpat
    do
--[[ The program proper expects events to be signalled by blank-delimited
ASCII characters. However, popular UTF-8 symbols are allowed, and these do
not need to be blank-delimited". Note that values below are ]]
local ttab = { ["†"] = ' + ', ["≈"] = " ~ ", ["÷"] = " %% ", [" "] = " " }
sanitize = function (input)
  local lno=0
  for line in input:gmatch"[^\n]*" do
    if line:match(endinput) then break end
    lno = lno+1
    for date in line:gmatch"%d%d[/-]?%d%d[/-]?%d%d[/-]?%d%d" do
      if not date:match"%d%d%d%d[/-]%d%d%d%d" then
        print(
          ("Line %s: dubious substring '%s' looks like invalid date format"):
          format(lno,date))
      end
    end
  end
  for k,v in pairs(ttab) do 
    input = input:gsub(k,v)
  end
  return input
end
-- saf event symbols, one-byte ASCII version 
local symbol = { 
  BIRT = "*", CHR = "~", DEAT = "+", BURI = "#", OCCU = "?", RESI = "@", 
  NOTE = "!", COMM = ";", DIV = "%" }  
event_symbols = ";~+!?@#*%%"
Event = {}
for k,v in pairs(symbol) do
  Event[v] = k
end
textpat = ("^([^%s]*)()"):format(event_symbols)
eventpat =  (" ([%s]) ()"):format(event_symbols)
    end

  do
local spouse_code="^x+$"
local child_code="^(%l%d+)$"
process = function(fullcode,line,indi,fam)
  local code, data = line:match"^%s*(%S+)%s+(.*)"
  if code:match(spouse_code) then
    if fullcode=="" then code = "a" .. code
    else code = fullcode..code
    end
    local person, marr
    local div = data:match"%% ()"
    if div then --- there is a divorce
      marr = data:sub(1,div-3)
      div, person = saftxt.event(data:sub(div),true)
    else
       marr, person = saftxt.event(data) 
    end
    fam:append(code,marr)
    if div then 
      fam:modify(code,"1 DIV\n"..saftxt.placedate(div)) 
    end
    indi:append(code,person)
    saftxt.crossref_spouse(indi,fam,code)
  elseif code:match(child_code) then 
    local pos = fullcode:match("()"..code:sub(1,1)) or #fullcode+1
    fullcode = fullcode:sub(1,pos-1) .. code
    indi:append(fullcode,data)
    saftxt.crossref_child(indi,fam,fullcode) 
  elseif #indi==0 then
    indi:append("a",line)
  else error("Bad input: "..line)
  end
  return fullcode
end  
  end

shipout = function(tbl,sep)
  local t = {}
  for k,v in ipairs(tbl) do
    if type(v) == 'table' then t[k] = shipout(v,sep)
    elseif v~='' then t[#t+1] = tostring(v)
    end
  end
  if #t>0 then return table.concat(t,sep) end
end

trim = function(str)
  return str:gsub("^%s+",""):gsub("%s+$","")
end

    do 
local woordjies = "De,Der,Den,Van,Du,Da,Le,La"
local accented = {["É"]="é"}
normalize = function (name)
  name = (" "..name):lower()
  name = name:gsub(" %l",string.upper)
-- Handle selected accented letters
  name = name:gsub("(%S)("..utf8.charpattern..")",function(x,y)
    if accented[y] then return x..accented[y] end
    end)
  for prep in woordjies:gmatch"%a+" do
    name = name:gsub(prep.." ",string.lower)
  end
  name = trim(name)
  return name
end
    end

local INDI, FAM = saftxt.INDI, saftxt.FAM
INDI.__index = INDI
FAM.__index = FAM

INDI.append = function(self,code,data)
  local newindi = INDI.new(data,code)
  newindi.code = code
  self[#self+1] = newindi
  self[code] = newindi
end

FAM.append = function(self,code,marr)
  local newfam = FAM.new(marr,code)
  newfam.code = code
  self[#self+1] = newfam
  self[code] = newfam
end

FAM.modify = function(self,code,data)
  assert(data,"FAM.modify may not be called with nil data")
  local fam = self[code]
  assert(fam,"Family "..code.." does not exist yet")
  fam[#fam+1] = data
end

    do
local subrec = {BIRT=true,CHR=true,DEAT=true}
INDI.new = function(data,code)
  local name,pos = data:match(textpat)
  data = ' '..data:sub(pos)
  local rec = {("0 @I%s@ INDI"):format(code)}
  rec[#rec+1], rec.surname = saftxt.NAME(name,INDI.surname)
  if not INDI.surname then INDI.surname = rec.surname end
  local events = {}
  for k,v in data:gmatch(eventpat) do
    local evt = Event[k]
    if evt == "COMM" then evt = "NOTE" end
    assert(evt,"No event for '"..k.."'")
    events[#events+1] = {evt,v}
  end
  if #events==0 then return rec end
  local lastevent = events[#events][2]
  local endnote = data:sub(lastevent):match"(); "
  if endnote then
    events[#events+1] = {"NOTE", lastevent+endnote+1}
  end
  for j,event in ipairs(events) do
    local evt = event[1]
    local rt = #data
    if j<#events then
      rt = events[j+1][2]-3
    end
    local v = trim(data:sub(event[2],rt))
    if subrec[evt] then
      pd = saftxt.placedate(v) 
      if pd then v = "\n" .. pd end
    end
    rec[#rec+1] = ("1 %s %s"):format(evt,v)
  end  
  return rec
end
    end

FAM.new = function(marr,code)
  local rec = {("0 @F%s@ FAM"):format(code)}
  marr = marr and saftxt.placedate(marr)
  if marr then
    rec[#rec+1] = ("1 %s\n%s"):format("MARR",marr)
  end
  return rec
end

saftxt.event = function(data)
  local head = data:match(textpat)
  assert(head,data.." does not match "..textpat)
  local pos,tail = head:match"%d%d%d%d()%s*()"
  if not pos then
    pos,tail = head:match" %- ()%s*()"
  end
  if not pos then return nil, data end
  return data:sub(1,pos-1),data:sub(tail)
end

    do Month = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug",
       "Sep","Oct","Nov","Dec"}
saftxt.placedate = function(text)
  local rec = {}
  local place, day, month
  local pos, year, note = text:match"()(%d%d%d%d)(.*)"
  if year then
    pos,date = text:sub(1,pos-1):match"()(%S*)$"
    if date then
      day,month = date:match"([^.]+)%.([^.]+)%.$"
      month = tonumber(month)
      if month then month = Month[month] end
      day = month and day
    end
  else
    pos, year, note = text:match"()%s(%-)%s(.*)"
  end
  if year then
    place = trim(text:sub(1,pos-1))
  end
  if place and not place:match"%S" then place = nil end
  if place or year or note then    
    if place then 
      rec[#rec+1] = ("2 PLAC %s"):format(place)
    end
    if year and year~="-" then
      local date = "2 DATE "
      if text:match" c%." or text:match"^c%."then date = date .. "ABT "
      elseif  text:match"<" then date = date .. "BEF "
      elseif  text:match">" then date = date .. "AFT "
      end
      day = tonumber(day)
      if day then date = date .. ("%d "):format(day) end
      if month then date = date .. month .. " " end
      rec[#rec+1] = date..year
    end
    if note and note:match"%S" then
      note = trim(note)
      local age, pos = note:match"^%s*%(([^.]+%.[^.]+%.[^.]+)%)%s*()"
      if not age then 
        age, pos = note:match"^%s*%(([^.]+%.[^.]+)%)%s*()"
      end
      if age then 
        rec[#rec+1] = ("2 AGE %s"):format(age)
        if pos <= #note then
          rec[#rec+1] = ("2 NOTE %s"):format(note:sub(pos))
        end
      else rec[#rec+1] = ("2 NOTE %s"):format(note)
      end
    end
  end
  return shipout(rec,"\n")
end
   end

local is_capitalized = function(word)
  return word == word:upper() and not word:match"%.$" and not word:match"}"
end

local pick_out_name = function(text)
  local words = {}
  local first, last
  for word in text:gmatch"%S+" do
    words[#words+1] = word
    if is_capitalized(word) then
      first = first or #words
      last = #words
    end
  end
  if last then return 
    table.concat(words,' ',1,first-1),
    table.concat(words,' ',first,last),
    table.concat(words,' ',last+1,#words)
  end
end

saftxt.NAME = function(text,surname)
  local rec = {}
  local sex, nick
  surname = surname or ''
  local pre, name, post = pick_out_name(text) 
  if not name then 
    name = surname
    pre, post = text:match"(.*)({.*})"
    if not pre then
      pre = text
      post = ''
    end
  end
  local info = post:match"{.*}"
  post = post:gsub("{.*}","")
  if info then
    sex = info:match"[FM]" 
  end
  name = normalize(name)
  local k1,k2 = pre:match'()%b""()'
  if k2 then
    nick = pre:sub(k1+1,k2-2)
    pre = trim(pre:sub(1,k1-1)) .. " " ..trim(pre:sub(k2))
  end
  rec[#rec+1] = ("1 NAME %s/%s/%s"):format(pre,name,post)
  if nick then rec[#rec+1] = ("2 NICK %s"):format(nick) end
  if sex then 
    rec[#rec+1] = ("1 SEX %s"):format(sex) 
  end
  return shipout(rec,"\n"), name
end

local isfemale = function(person)
  for k,v in ipairs(person) do if v:match"SEX F" then 
    return true 
  end end
end

-- add FAMS, HUSB and WIFE subrecords  
saftxt.crossref_spouse = function(indi,fam,code)
  local spouse = code:match"([^x]*)"
  local husb, wife = spouse,code
  if isfemale(indi[spouse]) then
    husb,wife = code,spouse
  end
  table.insert(indi[code],("1 FAMS @F%s@"):format(code))
  table.insert(indi[spouse],("1 FAMS @F%s@"):format(code))
  table.insert(fam[code],("1 HUSB @I%s@"):format(husb))
  table.insert(fam[code],("1 WIFE @I%s@"):format(wife))
end 

-- add FAMC and CHIL subrecords
saftxt.crossref_child = function(indi,fam,code)
  local parent = code:match"(.*)%l%d+$"
  if parent == '' then parent = "a" end
  local famc = parent.."x"
  if fam[famc.."x"] then 
    print("Warning: there is a second marriage for "..parent)
  end
  table.insert(indi[code],("1 FAMC @F%s@"):format(famc))
  table.insert(fam[famc],("1 CHIL @I%s@"):format(code))
end  

main()

