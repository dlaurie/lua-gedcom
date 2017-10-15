--- lifelines.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- LifeLines functions on GEDCOM objects.

-- See 'gedcom.lua' for the documentation of GEDCOM objects. This module
--    extends functionality by adding methods to the GEDCOM table and 
--    defining EVENT, BIRT, CHR, DEAT, BURI, MARR method tables. 
-- The documentation of the LifeLines Programming System and Report 
--    generator remains largely valid for the implemented functions, except 
--    that iterators follow Lua syntax: see comments. Note that Lua does 
--    not allow expressions to be written to output automatically.

-- Many LifeLines functions have been moved into `gedcom.lua` because they
-- are so natural and so inevitable that writing code without them would be
-- painful. If you see its name in the list but not its code below, it is 
-- already defined the moment that 'gedcom' has been required.

-- GEDCOM functions: fam firstfam firstindi forfam forindi indi lastfam 
--       lastindi to_gedcom write
--    These all require object-oriented calls with an object constructed
--    by gedcom.read(FILENAME), e.g. `ged:fam"F1". Doing so, rather than
--    making the functions global, allows the LifeLines module to support 
--    multiple  GEDCOM files.
-- INDI functions: birth burial death families father female givens male 
--       mother name nfamilies nspouses parents pn sex spousein spouses 
--       surname title
-- FAM functions: children firstchild husband lastchild marriage nchildren
--    spouses wife
-- EVENT functions: date day month place year

-- LifeLines features that are adequately and sometimes better served in Lua 
--    are not implemented, and there is no intention ever to do so. These
--    include e.g. program logic, string formatting and abstract (i.e. not
--    tied to GEDCOM ideas) data structures.

-- cache some routines as upvalues
local  tremove,      tunpack,      tconcat,      tsort = 
  table.remove, table.unpack, table.concat, table.sort
local append = table.insert
local Warning, Error = false, true

--- nonblank(s) is s if s is a non-blank string, otherwise nil
local function nonblank(s)
  if type(s)=='string' and s:match"%S" then return s end
  return nil
end

--- don't change the line below unless you understand the difference
--- between Lua 5.2 and Lua 5.3 'requre' and 'package'
local gedcom = require "gedcom" or require "gedcom.gedcom"

local meta = gedcom.meta
local GEDCOM, RECORD = 
  meta.GEDCOM, meta.RECORD
local Message = gedcom.util.Message

--- Tag-specific method tables
local INDI = meta.INDI
local FAM = meta.FAM
local DATE = meta.DATE
local NAME = meta.NAME
local EVENT = {}
for s in ("EVENT,BIRT,CHR,DEAT,BURI,MARR,DIV"):gmatch"%u+" do
  meta[s] = EVENT
end

local key_pattern = '^@(.+)@$'

-- GEDCOM functions

--- for indi,k in gedcom:forindi() do
GEDCOM.forindi = function(gedcom)
  local INDI = gedcom._INDI
  local k=0
  return function()
    k=k+1
    local indi = INDI[k]
    if indi then return indi,k end
  end
end      

--- for fam,k in gedcom:forfam() do
GEDCOM.forfam = function(gedcom)
  local FAM = gedcom._FAM
  local k=0
  return function()
    k=k+1
    local fam = FAM[k]
    if fam then return fam,k end
  end
end

GEDCOM.firstindi = function(gedcom)
  return gedcom._INDI[1]
end

GEDCOM.lastindi = function(gedcom)
  return gedcom._INDI[#gedcom._INDI]
end

GEDCOM.firstfam = function(gedcom)
  return gedcom._FAM[1]
end

GEDCOM.lastfam = function(gedcom)
  return gedcom._FAM[#gedcom._FAM]
end

-- Person functions

-- will not be implemented: key, soundex, inode, root
-- not implemented: fullname, trimname, nextsib, prevsib, nextindi, previndi
-- to be implemented: mothers, fathers, Parents

-- implemented as GEDCOM functions: indi forindi firstindi lastindi
-- implemented but not in lifelines: spousein
INDI.givens = function(indi)
  return indi.NAME.data:match "^[^%/]*"
end

INDI.birth = function(indi)
  return indi.BIRT
end

INDI.death = function(indi)
  return indi.DEAT
end

INDI.burial = function(indi)
  return indi.BURI
end

    do
local pronoun = {M={"He","he","His","his","him"},
                 F={"She","she","Her","her","her"}}
INDI.pn = function(indi,typ)
  return pronoun[indi:sex()][typ]
end
    end

INDI.title = function(indi)
  return indi.TITL.data
end

--- for spouse,family,k in indi:spouses() do
INDI.spouses = function(indi)
  local fams = indi:families()
  local n=0
  return function()
    local family, spouse
    repeat -- it is possible for a family to have no spouse!
      family, spouse = fams()
    until spouse or not family
    n=n+1
    if spouse then return spouse, family, n end
  end
end

INDI.nspouses = function(indi)
  local n=0
  for _ in indi:spouses() do
    n=n+1
  end
  return n
end

INDI.nfamilies = function(indi)
  local n=0
  for _ in indi:families() do
    n=n+1
  end
  return n
end

-- Family functions

-- will not be inmplemented: key fnode root
-- not implemented: nextfam prevfam
-- implemented as GEDCOM functions: fam forfam

FAM.marriage = function(fam)
  return fam.MARR
end

FAM.nchildren = function(fam)
  local n=0
  for _ in fam:children() do
    n=n+1
  end
  return n
end
  
FAM.firstchild = function(fam)
  return (fam:children()())
end

FAM.lastchild = function(fam)
  local child
  for ch in fam:children() do child=ch end
  return child
end

--- for spouse,k in fam:spouses() do
FAM.spouses = function(fam)
  local k=0
  return function()
    repeat
      k=k+1
      local spouse=fam[k]
    until not spouse or spouse.tag=='HUSB' or spouse.tag=='WIFE'
    return fam.prev:indi(spouse.data),spouse and k
  end
end

-- Event functions

EVENT.date = function(event)
  return event.DATE and event.DATE.data
end

EVENT.place = function(event)
  return event.PLAC and event.PLAC.data
end

EVENT.year = function(event)
  return event.DATE and event.DATE:year()
end

EVENT.month = function(event)
  return event.DATE and event.DATE:month()
end

EVENT.day = function(event)
  return event.DATE and event.DATE:day()
end

EVENT.status = function(event)
  return event.DATE and event.DATE:status()
end

-- Additional functions beyond what is in gedcom.lua. They can 
-- be seen as applications of LifeLines.

FAM.check = function(fam,options)
  local msg = fam.msg or Message()
  options = options or {}
  fam.msg = msg
  if fam.HUSB then -- TODO
  else msg:append("Family %s has no husband",fam.key) 
  end
  if fam.WIFE then -- TODO
  else msg:append("Family %s has no wife",fam.key) 
  end
  if options.chronological then
    local prev
    for child in fam:children() do
      if prev and child:birthyear() and prev:birthyear() then
        local compare = prev.BIRT.DATE:compare(child.BIRT.DATE)
        if compare==1 or compare==2 then
          msg:append("In family %s child %s should come after child %s",
          fam.key, prev.key, child.key)
        end
      end
      prev = child
    end
  end
end

INDI.check = function(indi,options)
  local msg = indi.msg or Message()
  indi.msg = msg
  local birthyear, deathyear = indi:birthyear(), indi:deathyear()
  local date_error
  if indi.BIRT then
    if indi.DEAT then
      local compare = DATE.compare(indi.BIRT.DATE,indi.DEAT.DATE)
      if compare==1 or compare==2 then date_error = true end
    end
  else
    date_error = true
  end
  if date_error then msg:append("%s %s ",indi.key,indi:refname()) end
end
    

GEDCOM.check = function(gedcom,options)
  for indi in gedcom:forindi() do
    indi:check(options)
  end
  for fam in gedcom:forfam() do
    fam:check(options)
  end
end

-- Superseded by Toolkit functions in gedcom.lua
--[[---- Subcollections
-- If you make a new collection of individuals selected from a larger
-- collection, the new GEDCOM might lack some families referred to.
-- If you included those families as you go along, some individuals
-- not included in the collection might be left over in those families.

--- gedcom:prune()
-- remove individuals not in the container from families 
GEDCOM.prune = function(gedcom)
  local schedule = {}
  for fam in gedcom:forfam() do
    for k=#fam,1,-1 do 
      if indi.tag=='INDI' and not gedcom[indi.key] then
        tremove(fam,k)
      end
    end
  end
end

--- gedcom:make_families()
-- Create families from individuals in the container
GEDCOM.make_families = function(gedcom)
  for indi in gedcom:forindi() do
    for tag in ("FAMC,FAMS"):gmatch"[^,]+" do
      for field in indi:tagged(tag) do
        fam = gedcom:new_family(field.data:match(key_pattern))
        fam:include(indi,tag)
      end
    end
  end
end

--- family:include(indi,tag)
-- Add an item for this individual, as HUSB, WIFE or CHIL depending on
-- whether 'tag' is FAMS or FAMC.
FAM.include = function(family,indi,tag)
  local item
  if tag=='FAMC' then 
    item=ITEM.new('CHIL',key_format:format(indi.key))
  elseif tag=='FAMS' then
    if indi:male() then
      item=ITEM.new('HUSB',key_format:format(indi.key))
    elseif indi:female() then
      item=ITEM.new('WIFE',key_format:format(indi.key))
    else assert(false,"Neither hisband nor wife")
    end
  else assert(false,"Neither FAMS nor FAMC") -- HIESA
  end
end

--- gedcom:new_family(key)
-- Return the family with the given key, making a new one if necessary
GEDCOM.new_family = function(gedcom,key)
  local fam = gedcom[key] 
  if not fam then
    fam = FAM.new(key)
    gedcom:append(fam)
  end
  return fam
end  
--]]
  
