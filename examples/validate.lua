--- validate.lua © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Validate a GEDCOM file

gedcom = require "gedcom"
gedfilename = arg[1]
if not gedfilename then print [[
  Usage: 

    lua validate.lua GEDCOM_FILENAME [CUSTOMIZE_FILENAME]
]]
  return
end

OK, msg = pcall(dofile, arg[2] or "customize.lua")

if OK then
  gedcom:customize{template=template; whitelist=whitelist; synonyms=synonyms}
  ged.msg:customize(translate)
elseif io.open"customize.lua" then  
  print("Loading/executing fie 'customize.lua' failed; message was:")
  print(msg)
  print("I shall continue, but without customizing")
end

ged,msg = gedcom.read(gedfilename)
if not ged then 
  print ("Could not read file "..gedfilename)
  return
end

print(-ged.msg)

msg = ged:validate()

print(-msg)

