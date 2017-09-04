--- lifelines.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- LifeLines functions on GEDCOM objects.

-- See 'gedcom.lua' for the documentation of GEDCOM objects. This module
--    extends functionality by adding methods to the GEDCOM table and defining
--    INDI, FAM, EVENT and DATE tables. The documentation of the LifeLines 
--    Programming System and Report generator remains largely valid for the
--    implemented functions, except that iterators follow Lua syntax: see 
--    comments. Note that Lua does not allow expressions to be written to 
--    output automatically.

-- GEDCOM functions: build fam firstfam firstindi forfam forindi
--    indi lastfam lastindi to_gedcom write
--    These all require object-oriented calls with an object constructed
--    by gedcom.read(FILENAME), e.g. `ged:fam"F1". Doing so, rather than
--    making the functions global, allows the LifeLines module to support 
--    multiple  GEDCOM files.
-- INDI functions: birth burial death families father female givens male mother
--    name nfamilies nspouses parents pn sex spousein spouses surname title
-- FAM functions: children firstchild husband lastchild marriage nchildren
--    spouses wife
-- EVENT functions: date day month place year
-- DATE functions: day month status year

-- LifeLines features that are adequately and sometimes better served in Lua 
--    are not implemented, and there is no intention ever to do so.

-- cache some routines as upvalues
local tremove, tunpack, tconcat = table.remove, table.unpack, table.concat
local append = table.insert

local gedcom = require "gedcom"
local meta = gedcom.meta
local GEDCOM = meta.GEDCOM

--- Method tables
local INDI, FAM, EVENT, DATE = {}, {}, {}, {}
meta.INDI, meta.FAM = INDI, FAM
meta.BIRT, meta.MARR, meta.BURI =  EVENT, EVENT, EVENT
meta.DATE = DATE

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

GEDCOM.indi = function(gedcom,key)
  local indi = gedcom[key]
  if indi and indi.tag == "INDI" then return indi end
end

GEDCOM.fam = function(gedcom,key)
  local fam = gedcom[key]
  if fam and fam.tag == "FAM" then return fam end
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

    do
local name_pattern = '^([^/]-)%s*/([^/]+)/%s*([^/]*)$'
INDI.name = function(indi,capitalize)
  local pre, surname, post = indi.NAME.data:match(name_pattern)
  if capitalize then surname = surname:upper() end
  local buf = {}
  append(buf,pre); append(buf,surname); append(buf,post)
  return tconcat(buf,' ')
end
    end

INDI.surname = function(indi)
  return indi.NAME.data:match "/(.*)/"
end

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

INDI.father = function(indi)
  return indi:parents():husband()
end

INDI.mother = function(indi)
  return indi:parents():wife()
end

INDI.sex = function(indi)
  return indi.SEX.data
end

INDI.male = function(indi)
  return indi:sex() == 'M'
end

INDI.female = function(indi)
  return indi:sex() == 'F'
end

    do
local pronoun = {M={"He","he","His","his","him"},
                 F={"She","she","Her","her","her"}}
INDI.pn = function(indi,typ)
  return pronoun[indi:sex()][typ]
end
    end

INDI.parents = function(indi)
  return indi.prev[indi.FAMC.data]
end

INDI.title = function(indi)
  return indi.TITL.data
end

--- indi:spousein(fam) 
-- if indi is a parent in the family, then the other parent, if any, 
-- is returned, otherwise nothing.
INDI.spousein = function(indi,fam)
  local husband, wife = fam:husband(), fam:wife()
  if indi == husband then return wife
  elseif indi == wife then return husband
  end
end

--- for family,spouse,k in indi:families() do
INDI.families = function(indi)
  local k=0   -- line in INDI record
  local n=0   -- number of family
  return function()
    local fam
    repeat
      k=k+1
      fam = indi[k]
    until not fam or fam.tag == "FAMS"
    if not fam then return end
    n = n+1
    fam = indi.prev:fam(fam.data)
    return fam, indi:spousein(fam), n
  end
end

--- for spouse,family,k in indi:spouses() do
INDI.spouses = function(indi)
  local fams = indi:families()
  local n=0
  return function()
    local family, spouse
    repeat 
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

FAM.husband = function(fam)
  return fam.prev:indi(fam.HUSB.data)
end

FAM.wife = function(fam)
  return fam.prev:indi(fam.WIFE.data)
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

--- for child,k in fam:children() do
FAM.children = function(fam)
  local k=0
  local child
  return function()
    repeat
      k=k+1
      child = fam[k]
    until not child or child.tag=='CHIL'
    if not child then return end
    return fam.prev:indi(child.data),child and k
  end
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
  return event.DATE.data
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
  return event.DATE and event.DATE:month()
end

-- Date functions

-- Adds fields to a DATE record
    do 
local parse_date = gedcom.glob.date
DATE._init = function(date)
  date._year, date._month, date._day, date._status = parse_date(date.data) 
end
    end  

DATE.day = function(date)
  if not date._year then date:_init() end
  return date._day
end

DATE.month = function(date)
  if not date._year then date:_init() end
  return date._month
end

DATE.year = function(date)
  if not date._year then date:_init() end
  return date._year
end 

DATE.status = function(date) 
  if not date._year then date:_init() end
  return date._status
end 


