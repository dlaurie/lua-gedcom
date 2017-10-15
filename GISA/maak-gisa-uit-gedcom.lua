-- maak-gisa-uit-gedcom.lua © 2017 Dirk Laurie 
-- Copy, modify, distribute etc. freely, but always include the full 
-- license as given at the end of this document.

--- separate 'arg' into options and positional arguments
cl_opt, cl_arg = {}, {}
    do
for k,v in ipairs(arg) do
  local opt = v:match"^-(.*)"
  if opt then
    local param,value = opt:match"([^=]*)=(.*)"
    if not param then param,value=opt:match"^(%u)(.*)" end
    if param then cl_opt[param] = opt
    else cl_opt[opt]=true
    end
  else
    cl_arg[#cl_arg+1]=v
  end
end
    end

if arg[-1]=='-i' or arg[-1]=='-h' then
  print [[
Gebruik so: 

   lua [-i] maak-gisa-uit-gedcom.lua [NAAM] [Van] [-Ikode] [-C] [-y]

   -i           Gee geleentheid vir veranderings met die hand.
   NAAM         Die GEDCOM-lêer se naam is "NAAM.ged" of "NAAM.GED"
   Van          Die familienaam is "Van".
   -Ikode       Die I-kode van die stamvader (bv "-I1")
   -C           Annoteer die uitvoer krities
   -y           Aanvaar alle voorstelle wat die program maak outomaties.

Alles in vierkantige hakies is opsioneel. Vrae sal gevra word as jy dit nie
verskaf nie. By party vrae is daar 'n wenk. Soms is dit 'n hele woord; 
dan is die hele woord 'n voorstel vir jou antwoord. Soms is daar net 'n 
paar letters waarvan een 'n hoofletter is: daardie hoofletter is die 
voorgestelde antwoord. As die voorstel aanvaarbaar is, hoef slegs Enter 
gedruk te word, anders moet 'n ander woord, of een van die ander letters, 
soos die geval mag wees, ingetik word, gevolg deur Enter. As jy "-y"
gespesifiseer het, verskyn die vraag steeds maar die voogestelde antwoord
word gebruik sonder dat jy Enter hoed te druk.
]]
end

if arg[-1]=='-h' then return end

local function prompt(msg,suggestion,ny)
  io.write(msg,' ')
  if suggestion then
    io.write('['..suggestion..'] ')
  end
  local ans = ny or suggestion
  if cl_opt.y then
    io.write"\n"
  else
    local line = io.read()  
    if #line>0 then
      ans = line
    end
  end
  return ans
end

local function janee(msg,ny)
  local suggestion = 'jn'
  if ny=='J' then suggestion='Jn'
  elseif ny=='N' then suggestion='jN'
  end
  local ans = prompt(msg,suggestion,ny)
  return ans:upper():match'^J' == 'J'
end

local retry=0
while not gedfile and retry<2 do
  filename = prompt("Naam van GEDCOM-lêer?",cl_arg[1])
  if filename then
    gedfile = io.open(filename) 
    if not gedfile then 
      gedfile = io.open(filename..".ged")
      if gedfile then filename = filename..".ged" end
    end
  end
  if not gedfile then print"Jy kry nog een kans." end
  retry = retry+1
end

if gedfile then
  gedfile:close()
else
  print("Ek kry nie so 'n lêer nie. Jammer, maar totsiens!")
  os.exit(-1)
end

toSAF = require "gedcom.ged2saf"
lifelines = require "gedcom.lifelines" 
gedcom = require "gedcom.gedcom" 
require "gedcom.template"

ged, msg = gedcom.read(filename)
if not ged then
  print("Die lêer lyk nie na goeie GEDCOM nie. Die foutboodskap is:")
  print(msg)
  os.exit(-1)
end

filename = filename:match"(.+)%.ged$" 
        or filename:match"(.+)%.GED$" 
        or filename

filename_lua = filename..".lua"
korreksies = io.open(filename_lua)
if korreksies then 
  korreksies:close() 
  korreksies = filename_lua
else
  korreksies = prompt("Naam van jou korreksielêer indien enige? ","")
  if not korreksies:match"%S" then korreksies=nil end
end

if korreksies then
  print("Ek lees bywerkings vanaf ",korreksies)
  local code, msg = loadfile(korreksies)
  if not code then
    print("Dit wou nie laai nie. Die foutboodskap is:")
    print(msg)
    os.exit(-1)
  end
  bywerkings = code()
end

bywerkings = bywerkings or {}

-- Die bywerkings gee dalk 'n stamvader, bv 
--  {name="Pieter Erasmus", lifespan="1672-1731"}
local stamvader 
local forefather = bywerkings.forefather
if forefather then
  forefather = ged:find(forefather)
  if #forefather == 1 then
    stamvader = forefather[1]
  else
  print"Die bywerkings stel voor:"
  for k,v in pairs(forefather) do print(k,"'"..v.."'") end
  stamvader = nil
    print("Daardie voorstel klop met "..#forefather.." persone")
  end
end

-- die "I" opsie kry egter voorrang bo alles
if cl_opt.I then
  local sv = ged["I"..cl_opt.I]
  stamvader = sv or stamvader
end

local surname = filename
if stamvader then
  surname = stamvader:surname() or surname
end

opsie = {}

function printem(ged,persone)
  local outname = filename..".html"
  local outfile,msg = io.open(outname,"w")
  if cl_opt.C then opsie.critic = true end
  opsie.maleline = janee("Net afstammelinge in die manlike lyn?","J")
  opsie.prefix = prompt("Generasies begin by: ","b")
  local html = janee("Wil jy jou eie prototipe verskaf","N")
  if html then
    local voorbeeld = prompt("Wat is die naam van jou prototipe?","GISA.html")
    local vb_html = io.open(voorbeeld)
    if vb_html then
      opsie.html = vb_html:read"a"
    else
      print("Ek kan nie daardie lêer lees nie. Ek gaan voort met die ingeboude voorbeeld.")
    end
  end
  if outfile then 
    local stamboom = ged:toSAF(persone,opsie)
    if not stamboom then print("Leë stamboom")
    else 
      outfile:write(stamboom):close() 
      print(outname.." is uitgeskryf")    
    end
  else print(msg)
  end
  io.open(filename..".log","w"):write(ged.msg:concat()):close()
  print("'n Rapport oor jou GEDCOM staan in "..filename..".log")
end

local voorstel = (stamvader and stamvader.key) or "I1"
ged:update(bywerkings)

function klaar()
  local persone = prompt(
     "Gee die kodes I1,I2,... van die verlangde stamvaders.",voorstel)
  printem(ged,persone)
end

function kinders(key)
  if not ged[key] then return end
  for child in ged[key]:children() do
    print(child.key,child:refname())
  end
end

--[[
 if not stamvader then
if false then
  local surname = prompt("Familienaam van stamvader",cl_arg[2] or surname)
  stamvader = ged:alpha(surname)
end

if stamvader then 
  voorstel = stamvader.key 
  print("Die stamvader is blykbaar ",voorstel,stamvader:refname());
else
  print"Geen stamvader gevind nie."
end
--]]

if arg[-1]=='-i' and janee(
    "Wil jy iets met die hand doen?",
    "J") then
  if stamvader then 
    print(("Tik kinders'%s' om te sien wie sy kinders was."):
    format(stamvader.key)) 
  end
  print("Tik 'klaar()' as jy weet watter kodes die verlangde stamvaders het.")
else  
  if stamvader then printem(ged,voorstel) end
end

--[[
Copyright 2017 Dirk Laurie.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]
