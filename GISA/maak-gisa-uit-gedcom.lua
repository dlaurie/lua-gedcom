if true then
  print [[
Gebruik so: 

   lua maak-gisa-uit-gedcom.lua 

Vrae sal gevra word. By party vrae is daar 'n wenk. Soms is dit 
'n hele woord; dan is die hele woord 'n voorgestelde antwoord.
Soms is net 'n paar letters waarvan een 'n hoofletter is: daardie 
hoofletter is die voorgestelde antwoord. As die voorstel aanvaarbaar 
is, hoef slegs Enter gedruk te word, anders moet 'n ander woord, of
een van die ander letters, soos die geval mag wees, ingetik word,
gevolg deur Enter.
]]
end

local function prompt(msg,suggestion,ny)
  io.write(msg,' ')
  if suggestion then
    io.write('['..suggestion..']')
  end
  local ans = io.read()  
  if #ans>0 then
    return ans
  end
  return ny or suggestion
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
  filename = prompt("Naam van GEDCOM-lêer?",arg[1])
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

ged, msg = gedcom.read(filename)
if not ged then
  print("Die lêer lyk nie na goeie GEDCOM nie. Die foutboodskap is:")
  print(msg)
  os.exit(-1)
end

filename = filename:match"(.+)%.ged$" 
        or filename:match"(.+)%.GED$" 
        or filename
io.open(filename..".log","w"):write(msg):close()

print("'n Rapport oor jou GEDCOM staan in "..filename..".log")
if janee("Wil jy die rapport ook nou sien?","N") then
  print(msg)
end

if janee("Het jy 'n lêer met voorkeure?","N") then
  voorkeur = prompt("Wat is die naam daarvan?","voorkeure.lua")
  ok, msg = pcall(dofile,voorkeur)
  if not OK then
    print("Dit wou nie laai nie. Die foutboodskap is:")
    print(msg)
    os.exit(-1)
  end
end

function printem(ged,persone)
  local outname = filename..".txt"
  local outfile,msg = io.open(outname,"w")
  local maleline = janee("Net afstammelinge in die manlike lyn?","J")
  if outfile then 
    outfile:write((ged:toSAF(persone,{maleline=maleline}))):close()
    print("GISA-teksformaat staan op "..outname..". "..
[[
Dit moet met 'n ander program omgeskakel word na GISA-dokumentformaat.
]])    
  else print(msg)
  end
end

local voorstel

function klaar()
  local persone = prompt(
     "Gee die kodes I1,I2,... van die verlangde stamvaders.",voorstel)
  printem(ged,persone)
end

function kinders(key)
  if not ged[key] then return end
  for child in ged[key]:children() do
    print(child.key,child:toSAF())
  end
end

local stamvader = ged:alpha()
voorstel = stamvader.key
print("Die stamvader is dalk",voorstel,stamvader:refname());

if arg[-1]=='-i' and janee(
    "Wil jy met die hand rondsnuffel in, of opknap aan, die GEDCOM-gegewens?",
    "J") then
  print(("Tik kinders'%s' om te sien wie sy kinders was."):
    format(stamvader.key))
  print("Tik 'klaar()' as jy weet watter kodes die verlangde stamvaders het.")
else
  printem(ged,voorstel)
end


