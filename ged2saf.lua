--- ged2saf.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Represent a GEDCOM file in SAF format.

-- See 'gedcom.lua' and 'lifelines.lua' for the documentation of GEDCOM objects
-- and the LifeLines functions acting on them. This module extends their
-- functionality by adding toSAF methods to the GEDCOM, INDI, FAM, EVENT, 
-- NOTE, PLACE and DATE tables. 

-- cache some routines as upvalues
local tinsert, tunpack, tconcat = table.insert, table.unpack, table.concat
-- Why not just `append=tinsert`? To avoid `append(t,myfunc())` failing when
-- myfunc returns a vararg of length 0.
local append = function(tbl,x) tinsert(tbl,x) end

local lifelines = require "gedcom.lifelines" 
local gedcom = require "gedcom.gedcom" 
local meta = gedcom.meta
local GEDCOM, EVENT, INDI, FAM = meta.GEDCOM, meta.EVENT, meta.INDI, meta.FAM
meta.PLAC = meta.PLAC or {}
meta.NOTE = meta.NOTE or {}
meta.NAME = meta.NAME or {}
local DATE, PLAC, NOTE = meta.DATE, meta.PLAC, meta.NOTE

local LIFESPAN, EVENTS, PARENTS, BIO, SURNAME = 0x1, 0x2, 0x4, 0x8, 0x10

-- The argument "options" to the toSAF routines can be a table redefining 
-- any of the following.
--local 
default = { 
-- output format
  gisa_markup = true;      -- insert bold, italic, etc.
  bold_parents = false;    -- parents of spouse also in bold
  capitalize = true;       -- surname in capitals
-- preferred symbols
  BIRT = "*";
  CHR = "≈";
  DEAT = "†";
  BURI = "#";
  MARR = 'x';
  DIV = "÷";
  liaison = '&';
  son_of = "s/v";
  daughter_of = "d/v";
  ABT = "c.";
  AFT = ">";
  BEF = "<";
  rchevron = "»";  -- old GEN2SA used this for notes
-- separators
  AND = " en ";    -- ' and ', including spaces
  indi_sep = ", ";  -- between events in an individual
  co_sep = ";";    -- after last event if there is a child-of clause
  tab = "\t";      -- between De Villiers code and name
  page = "\n\n\n";  -- between trees
  spouse = "  \n";  -- between spouses
  descendants = "\n\n";  -- between descendants
  note = ". ";  -- between events and note of individual
-- format strings
  name_markup = "**%s**";
  note_markup = "_%s_";
--    dates
  DMY = "%d.%02d.%04d";
  dMY = "-.%02d.%04d";
--  dmY = "-.-.%04d";
  dmY = "%04d";
--    ages
  YMD = "%dj%02dm%dd";
  YMd =  "%j%02d";
  Ymd =  "%j";
-- constants used for detail selection
  LIFESPAN = 0x1;
  EVENTS = 0x2; 
  PARENTS = 0x4;
  BIO = 0x8;
  SURNAME = 0x10
}

--- Inserts 'default' as fallback for 'options' unless it already
-- has a fallback
default.setoptions = function(options,overrides)
  overrides = overrides or {}
  if getmetatable(overrides) then return overrides
  else return setmetatable(overrides or {},{__index=options}) 
  end
end
 
--- nonblank(s) is s if s is a non-blank string, otherwise false
local function nonblank(s)
  return type(s)=='string' and s:match"%S" and s
end

local function heading(level,text)
  if not nonblank(text) then return end
  return ('#'):rep(level).." "..text
end
  
local function italics(s,markup)
  if not nonblank(s) then return end
  if markup == false then 
    return s
  else
    return "_"..s.."_" 
  end
end

local function bold(s,markup)
  if not nonblank(s) then return end
  if markup == false then 
    return s
  else
    return "**"..s.."**" 
  end
end

local function toSAF(object,...)
  if object and object.toSAF then return object:toSAF(...) end
end

PLAC.toSAF = function(place,options)
  return place.data
end

DATE.toSAF = function(date,options)
  options = default:setoptions(options)
  if not date._year then date:_init() end
  local day,       month,       year,       status = 
  date._day, date._month, date._year, date._status
  local dat = {}
  status = options[status]
  if day then append(dat,options.DMY:format(day,month,year))
  elseif month then append(dat,options.dMY:format(month,year))
  elseif year then append(dat,options.dmY:format(year))
  end
  if #dat>0 then
    return tconcat(dat)
  end
end

EVENT.toSAF = function(event,options)
  options = default:setoptions(options)
  local ev = {}
  append(ev,options[event.tag] or "?")
  append(ev,event.PLAC and event.PLAC:toSAF(options))
  append(ev,event.DATE and event.DATE:toSAF(options))
  append(ev,event.NOTE and event.NOTE:toSAF(options))
  if #ev>1 then return tconcat(ev," ") end   
end

NOTE.toSAF = function(note,options)
  if not nonblank(note.data) then return end  
  return italics(note.data:match"^[^\n]*",options.gisa_markup)
end

--- indi:toSAF(detail,options)
--- detail is the OR-ing together of
-- LIFESPAN  append lifespan (takes precedence over EVENTS)
-- EVENTS    append birth, christening, death, burial
-- PARENTS   append parents
-- BIO       append main note
-- SURNAME   include surname in the name
-- The above names are local in 'ged2saf.lua' and fields in 'default'
INDI.toSAF = function(indi,detail,options)
  options = default:setoptions(options)
  local omit_surname = (detail & SURNAME) == 0
  local ind = {}
  append(ind,bold(indi:name(options.capitalize,omit_surname),
    options.gisa_markup))
--  append(ind,indi:nickname(options))
  if (detail & LIFESPAN) > 0 then
    append(ind,indi:lifespan())
    ind = {tconcat(ind," ")}
--    append(ind,toSAF(indi.NOTE,options))
  elseif (detail & EVENTS) > 0 then
    append(ind,toSAF(indi.BIRT,options))
    append(ind,toSAF(indi.CHR,options))
    append(ind,toSAF(indi.DEAT,options))
    append(ind,toSAF(indi.BURI,options))
  end
  ind = tconcat(ind,options.indi_sep)
  local father, mother = indi:father(), indi:mother()
  if (detail & PARENTS) > 0 and (father or mother) then
    local co = options.child_of
    if indi:female() then co = options.daughter_of
    elseif indi:male() then co = options.son_of
    end
    local par = {}
    append(par,toSAF(father,LIFESPAN|SURNAME,
      {gisa_markup=false,note=", "},false))
    append(par,toSAF(mother,LIFESPAN|SURNAME,
      {gisa_markup=false,note=", "},false))
    ind = tconcat({ind, tconcat(par,options.AND)},
       options.co_sep..' '..co..' ')    
  end
  local note = toSAF(indi.NOTE,options)
  if note then 
    return ind .. options.note .. note
  else
    return ind
  end
end

local GISAprefix = function(old,new,n)
  new = new..n
  old = old..new
  return ("^%s^ ~%s~"):format(old,new)
end

--- indi:toSAFtree(prefix,options)
-- prefix: the De Villiers code of this person's ancestor
INDI.toSAFtree = function(indi,prefix,options)
  options = default:setoptions(options)
  local detail 
  local tree = {}
  local oldprefix = prefix or ''
  if nonblank(oldprefix) then --- this is a descendant
    detail = EVENTS
  else --- this is the stamvader
    detail = EVENTS | SURNAME | PARENTS
  end
  prefix = string.char((prefix or 'a1'):byte(-2,-2)+1)
  append(tree,indi:toSAF(detail,options))
  for spouse,fam,k in indi:spouses() do
    append(tree,options.MARR:rep(k)..options.tab..
      spouse:toSAF(EVENTS|PARENTS|SURNAME,options,false))
  end
  tree = {tconcat(tree,options.spouse)}
  if indi:male() or not options.maleline then
    for child,j in indi:children() do
      if prefix:match"^b" then
        append(tree,heading(2,prefix..j))
      end
      append(tree,GISAprefix(oldprefix,prefix,j)..options.tab..
        child:toSAFtree(oldprefix..prefix..j,options)) 
    end
  end
  return tconcat(tree,options.descendants)
end

--- ged:toSAF(root,options)
-- root: a single INDI or a collection
GEDCOM.toSAF = function(ged,root,options)
  options = options or {}
  options = default:setoptions(options)
  if type(root)=='string' then
    local r = gedcom.new()
    for key in root:gmatch"[^ ,;]+" do
      r[#r+1] = ged[key]
    end
    root=r
  end
  if rawget(root,'tag') == "INDI" then root = {root} end
  local saf = {}
  local msg = gedcom.util.Message()
  for _,indi in ipairs(root) do
     if indi.prev ~= ged then 
       msg:append("%s is not in the universe",indi:refname())
     end
     append(saf,heading(1,indi:surname():upper()))
     append(saf,indi:toSAFtree(nil,options))
  end
  return tconcat(saf,options.page).."\n", msg
end

--[[

local SAF = {options=default}   -- metatable for SAF structure
SAF.__index = SAF

-- add a layer of overrides
-- remove a layer of overrides
SAF.forgetoptions = function()
  local options = getmetatable(SAF.options).__index
  if not options then return end
  SAF.options = options 
end

-- Data structure for accumulating bits and pieces of output
SAF.new = function()
  return setmetatable({options=SAF.options},SAF)
end

SAF.append = function(saf,x)
  if nonblank(x) then append(saf,x) end
end

SAF.assemble = function(saf,delim)
  return tconcat(saf,delim or ' ')
end

SAF.event = function(saf,event,symbol)
  local options = saf.options
  local lst = {}
  lst[#lst+1] = symbol
  local place = event:place()
  if place then lst[#lst+1] = place:toSAF(options) end

  if #lst>1 then
    saf:append(s..tconcat(lst))
  end
  if event.NOTE then
    saf:append(saf:markup(event.NOTE.data,"italics"))
  end 
end

SAF.birth = function(saf,birth)
  SAF:event(birth,options.born)
end

SAF.death = function(saf,death)
  SAF:event(death,options.died)
end

SAF.baptism = function(saf,baptism)
  SAF:event(death,options.baptized)
end

SAF.burial = function(saf,baptism)
  SAF:event(death,options.buried)
end

SAF.divorced = function(saf,divorce)
  SAF:event(death,options.divorced)
end  

SAF.given = function(saf,given)
  saf:append(given)
end

INDI.baptism = function(indi)
  return indi.BAPT or indi.CHR
end

-- individual taken in isolation
INDI.toSAF = function(indi,saf)
  saf = saf or SAF:new()
  saf:given(indi:given())
  saf:surname(indi:surname())  
  local birth, death = indi:birth(), indi:death() 
  if options.short then
    if options.lifespan then
      saf:lifespan(birth:year(),death:year())
    end
  else
    saf:birth(birth)
    saf:death(death)
    saf:burial(indi:burial())
  end 
  if options.parents then
    saf:parents(indi:father():tosaf{short=true,lifespan=true})
  end
  return saf:assemble()
end

-- individual when set as spouse
INDI.toSAFasSpouse = function(indi,options)
  local SAF = newSAF(options)
end

return SAF
    
--[[
proc beskryf(persoon) {
  if(not(persoon)) { return() }
  fullname(persoon,1,1,80)
  if(geboorte, birth(persoon)) {
    " * " sagplace(geboorte) sagdate(geboorte)
  }
  if(gedoop, christening(persoon)) {
    "≈ " sagplace(gedoop) sagdate(gedoop)
  }
  if(dood, death(persoon)) {
    "† " sagplace(dood) sagdate(dood)
  }
  if(begrawe, burial(persoon)) {
    "Ω " sagplace(begrawe) sagdate(begrawe)
  }
}




  local name = indi:name(options.capitalize_surname)
  local 

/* persoon     IND     first parent in this family
   geslag      INT     generation number
   nommer      INT     number of person within family
*/
proc gen2sa(persoon,geslag,nommer) {
  if (gt(geslag,gens)) { return() }
  set(inkeep,mul(geslag,4))
  set(kode,deVPama(geslag,nommer))
  set(huwelik,"")
  set(kindno,0)
  set(vorige,0)
    /* vertoon voorouer */
  vooraf rjustify(" ",sub(geslag,1)) rjustify(kode,sub(inkeep,geslag)) " " 
  call beskryf(persoon) "\n"
    /* ---------------- */
  families (persoon, gesin, eggenoot, gesinnommer) {
    set(huwelik,concat(huwelik,"x"))
    if (gt(vorige,0))            /* was daar kinders uit die vorige huwelik? */
      { set(hkode,concat(kode,huwelik)) } /* herhaal dan eerste ouer se kode */
    else { set(hkode,huwelik) }  /* anders nie */
    vooraf rjustify(hkode,add(inkeep,1)) " " 
    if(troue, marriage(gesin)) {
      sagplace(troue) sagdate(troue)
    }    
    call beskryf(eggenoot) "\n" 
    set(vorige,nchildren(gesin))
    indiset(kinders)  /* Maak lys van kinders met geboortedatum */
    children(gesin,kind,j) {
      addtoset(kinders,kind,date2jd(birth(kind)))
    }
    valuesort(kinders)  /* sorteer van oudste na jongste */
    forindiset (kinders, kind, ongebruik, j) {
      incr(kindno)
      call gen2sa(kind,add(geslag,1),kindno)
    }
  } 
}



/*
 * @progname       sag.ll
 * @version        0.1
 * @author         Dirk Laurie
 * @category       
 * @output         HTML wrapping plain text, for now
 * @description

@(#)sag.ll	0.1 9/2/2017
*/

global(MAXLINES)
global(linecount)
global(gens)
global(teiken)   /* "html" or "pandoc" */
global(vooraf)   /* something needed at the start of every line; target-dependent */

proc main () {

/* Preferences */             
  set(teiken,"html")          /* Default target is html */
  if (t,getproperty("format")) { set(teiken,t) }
  set(I1,"I1")                /* Default progenitor is I1 */
  if (t,getproperty("start")) { set(I1,t) }
  set(voorvader,indi(I1))   
  set(gens, 100)                /*Default depth is practically infinite */
  if (t,getproperty("depth")) { set(gens,strtoint(t)) }
/* SAG Afrikaanse datumformate */
  complexpic(0,"c.%1")
  complexpic(3,"<%1")
  complexpic(4,">%1")
/* ----------- */

  set(MAXLINES,500)           /* set max report lines */
  set(linecount,0)            /* initialize linecount */
  dayformat(1)       /* leading zero before single digit days */
  monthformat(1)     /* leading zero before single digit months */
  set(charset,"utf-8")   /* Assume ancient GEDCOM */

  if (eq(teiken,"pandoc")) { set(vooraf,"| ") }  /* PanDoc markdown: line block */

  if (eq(teiken,"html")) {
"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head>
  <meta http-equiv=\"Content-Type\" content=\"text/html; charset="
charset
"\" />
</head>
<body>"
  "<PRE>\n" }

  call gen2sa(voorvader,1,1)

  if (eq(teiken,"html")) {
  "</PRE>\n"

"</body>
</html>" }
}


func deVPama(geslag,nommer) {
  return(concat(alpha(geslag),d(nommer)))
}

func christening(indi) {
    fornodes(indi,node) {
        if (index(" CHR ",upper(tag(node)),1)) {
            return(node)
        }
    }
    return(0)
}


/* Different datepics depending on whether day and/or month is missing */
func sagdate(gebeur) {
  datepic("%d.%m.%y ")   /* Probeer eers volledige datum */
  set(s,stddate(gebeur))
  if (le(index(s," ",1),2)) { /* volledige datum nie beskikbaar nie */
    datepic("%m.%y ")         /* Dalk maand en jaar? */
    set(s,stddate(gebeur)) 
    if (le(index(s," ",1),2)) { /* ook nie, dan jaar alleen */
      datepic("%y ")
    }
  }
  return (complexdate(gebeur))
}

func sagplace(gebeur) {
  if (plek,place(gebeur)) {
    if (j,index(plek,",",1)) {  /* Gooi alles na eerste komma weg */
      set(plek,substring(plek,1,sub(j,1)))
    }
    return(concat(plek," "))
  }
}


/******************************************************************************/

/*
   key_no_char:
     Return string key of individual or family, without
     leading 'I' or 'F'.
*/
proc key_no_char (nm) {
    set(k, key(nm))
    substring(k,2,strlen(k))
} 

--]]

--[[
-- siblua/gisa-saf.lua  © Dirk Laurie 2017  MIT license like that of Lua
-- Conversion of SibLua data structures to GISA's SAF format.
-- Adds methods to existing classes siblua.Crowd and siblua.Person:
--   Person.toSAF
--   Crowd.toSAF

local objects = require"siblua.objects"
local Crowd = objects.Crowd
local Person = objects.Person
local nonblank = objects.nonblank
local nonzero = objects.nonzero

local SAFdate = function(date,status)
-- status not yet available from WikiTree Apps
  local year,month,day
  if type(date) == 'table' then  -- as returned by os.date"*t"
    year,month,day = date.year,date.month,date.day
  elseif type(date)=='string' then   -- as provided by WikiTree API
    year,month,day = date:match"(%d%d%d%d)%-(%d%d)%-(%d%d)"
  else 
    return 
  end
  local D = {}
  local d = tonumber(day)
  local m = tonumber(month) 
  local y = tonumber(year) 
  assert(d and m and y and (y>0 or m==0 and d==0),date)
  assert(m>0 or d==0,date)
  if d>0 then D[#D+1] = day end
  if m>0 then D[#D+1] = month end
  if y>0 then D[#D+1] = year end
  if #D>0 then return table.concat(D,'.') end
end

local lifespan = function(birth,death)
  local b = nonzero(birth:match"%d%d%d%d") or ''
  local d = nonzero(death:match"%d%d%d%d") or ''
  if b~='' or d~='' then return ("(%s–%s)"):format(b,d) end
end

local child_of = {
  Afr = {Male="s.v.",Female="d.v.",Child="k.v.",AND="en"};
  Eng = {Male="s.o.",Female="d.o.",Child="c.o.",AND="and"};
}
local plain_formats = {
   Parents="%s %s %s %s",
   Parent="%s %s",
}
--- person:toSAF(options)
-- SAF representation of person as a string
-- 'options' is a table in which the following are recognized:
--   withSurname=false  Omit surname 
--   withParents=true   Any Lua true value will do
--   lang='Any'         Default is 'Afrikaans'. Specifying an unsupported
--                      language is tantamount to 'English'.
--   GISA=false         Don't apply GISA markup 
-- In the above, "=true" may be any Lua true value, but '=false' must be 
-- exactly the boolean value `false`.
Person.toSAF = function(p,options)
  options = options or {}
  local bold, birth, baptism, death, buried = "", "*", "~", "+", "$" 
  local Date = function(...) return ... end
  local remark = "\\ "
  if options.GISA~='false' then 
    bold, birth, baptism, death, buried, remark = 
      "**", "★", "≈", "†", "⚰", "»\\ "
    Date = SAFdate
  end
  local fmt = plain_formats
  local parts={}
  local function insert(item, format)
    if not nonblank(item) then return end
    if type(format)=="string" then item = format:format(item) end
    parts[#parts+1] = item
  end
  local insertEvent = function(code,place,date)
    date = Date(nonzero(date))
    place = nonblank(place)
    if not (place or date) then return end
    insert(place or date,code.."\\ %s")
    if place and date then insert(date) end
  end
---
  insert(p:givens())
  if not (options.withSurname == false) then
    insert(p:surname(options))
  end
  parts = {bold..table.concat(parts,' ')..bold}
  insertEvent(birth,p.BirthLocation,p.BirthDate)
  insertEvent(baptism,p.BaptismLocation,p.BaptismDate)
  insertEvent(death,p.DeathLocation,p.DeathDate)
  if options.withParents then while true do  -- one-pass loop to allow 'break'
    local father, mother = p:father(), p:mother()
    if not (father or mother) then break end
    father = father and father:name{withdates=lifespan}
    mother = mother and mother:name{withdates=lifespan}
    options.language = options.language or "Afrikaans"
    options.language = options.language:sub(1,3)
    local lang = child_of[options.language] or child_of.Eng
    local CO = p.Gender or "Child"  
    if father and mother then
      insert(remark..fmt.Parents:format(lang[CO],father,lang.AND,mother))
    else
      insert(remark..fmt.Parent:format(lang[CO],father or mother))
    end
    break
  end end  
  return table.concat(parts," ")
end

local function addDescendants (crowd,line,person,code,maleline)
  code=code or ''
  local lastletter = code:match"(%a)%d+$" or 'a'
  local nextletter = string.char(lastletter:byte()+1)
  if not person.Spouses then return end
  for n,spouse in ipairs(person.Spouses) do
    if not crowd[spouse] then
      print(person, "Person '"..spouse.."' is not in crowd")
    end
    spouse = crowd[spouse]    
    local spcode = code
    if code:match"%S" then spcode = ("^%s^ "):format(code) end
    if spouse then line[#line] = line[#line] .. "  \n" ..  -- new line but not new paragraph
      spcode..('×'):rep(n)..' '..spouse:toSAF{withParents=true} end
  end
  local j=0
  for n,spouse in ipairs(person.Spouses) do
    spouse = crowd[spouse]
    if person:male() or not maleline then
    for child in person:children(spouse) do
      j = j+1
      local shortcode = nextletter..j
      local newcode = code..shortcode
      line[#line+1] = ("^%s^ ~%s~ "):format(newcode,shortcode)..' '..
        child:toSAF{withSurname=false}
      addDescendants(crowd,line,child,newcode,maleline)
    end end
  end
end

--- crowd:toSAF(options)
-- SAF representation of a crowd as a string
--   `options` is a table in which all options of `person:toSAF` are
--    recognized, as well as the following:
--    `from=` The `Person` (or key of, in `crowd`) whose descendants 
--        are to be listed. If missing, a plausible choice is made.
--    `maleline=` Only list descendants in the male line, i.e. include 
--        daughters but not their children
--    `parsep=false` Do not put empty lines after paragraphs.
Crowd.toSAF = function(crowd,options,parsep)
  if parsep=='false' then
    parsep = "  \n"
  else
    parsep = "\n\n"
  end
  options = options or {}
  local line = {}
  local forefather = options.from 
  forefather = crowd[forefather] or forefather or crowd:forefather() 
  local line = {forefather:toSAF{withParents=true}}
  addDescendants(crowd,line,forefather,"",options.maleline)
  return table.concat(line,parsep)
end
--]]


