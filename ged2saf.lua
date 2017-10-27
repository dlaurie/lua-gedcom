--- ged2saf.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Represent a GEDCOM file in SAF format.

-- See 'gedcom.lua' and 'lifelines.lua' for the documentation of GEDCOM objects
-- and the LifeLines functions acting on them. This module extends their
-- functionality by adding toSAF methods to the GEDCOM, INDI, FAM, EVENT, 
-- NOTE, PLACE and DATE tables. 

-- BUGS  'x' not printed on spouse line when there is no marriage information.

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
meta.OCCU = meta.OCCU or meta.NOTE
meta.RESI = meta.RESI or meta.NOTE
local DATE, PLAC, NOTE = meta.DATE, meta.PLAC, meta.NOTE
local print = print

local LIFESPAN, EVENTS, PARENTS, BIO, SURNAME = 0x1, 0x2, 0x4, 0x8, 0x10

-- The argument "options" to the toSAF routines can be a table redefining 
-- any of the following.
--local 
default = { 
-- output format
  markup = 'html';
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
  child_of = 'k/v';
  ABT = "ca. ";
  AFT = ">";
  BEF = "<";
  rchevron = "»";  -- old GEN2SA used this for notes
-- separators
  AND = " en ";    -- ' and ', including spaces
  indi_sep = " ";  -- between events in an individual
  co_sep = ";";    -- after last event if there is a child-of clause
  note = ". ";  -- between events and note of individual
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

local pass = function(...) return ... end

local plain, markdown, html

plain = {
  Header = function(level,s) return s.."\n\n" end;
  Emph = pass;
  Strong = pass;
  fullDeV = pass;
  abbrDeV = pass;
  NewLine = "  \n";

  Person = function(s)
    return s .. "\n\n"
  end;

  Wrap = function(s)
    return s .. "\n"
  end;
}

markdown = {
  Header = function(level,text)
    if not nonblank(text) then return end
    return ('#'):rep(level).." "..text.."\n\n"
  end;

  Emph = function(s)
    if not nonblank(s) then return end
    return "_"..s.."_" 
  end;

  fullDeV = function(s)
    if not nonblank(s) then return end
    return "^"..s.."^" 
  end;

  abbrDeV = function(s)
    if not nonblank(s) then return end
    return "~"..s.."~" 
  end;

  Strong = function(s)
    if not nonblank(s) then return end
    return "**"..s.."**" 
  end;

  NewLine = "  \n";

  Person = function(s)
    return s .. "\n\n"
  end;

  Wrap = function(s)
    return s .. "\n"
  end;

}

html = {
  Header = function(lev, s)
    return "<h" .. lev .. ">" .. s .. "</h" .. lev .. ">\n"
  end;

  Emph = function(s)
    if not nonblank(s) then return end
    return "<i>" .. s .. "</i>"
  end;

  Strong = function(s)
    if not nonblank(s) then return end
    return "<b>" .. s .. "</b>"
  end;

  fullDeV = function(s)
    if not nonblank(s) then return end
    return "<span class=blind>" .. s .. "</span>" 
  end;

  Red = function(s)
    return '<span style="color:#C00000">'..s..'</span>'
  end;

  Green = function(s)
    return '<span style="color:#00C000">'..s..'</span>'
  end;

  Blue = function(s)
    return '<span style="color:#0000C0">'..s..'</span>'
  end;

  Brass = function(s)
    return '<span style="color:#A0A000">'..s..'</span>'
  end;

  abbrDeV = function(s)
    if not nonblank(s) then return end
    return "<code>" .. s .. "</code>"
  end;

  Tab = "&#9;";

-- newlines in the following two functions have no effect, 
-- but are very useful to humans that wish to read the HTML code
  NewLine = "</br>\n";

  Person = function(s,class)
    if class then return ("<p class=%s>%s</p>\n\n"):format(class,s)
    else return "<p>" .. s .. "</p>\n\n"
    end
  end;

  Wrap = function(s)
    local head, body, tail = html.document:match"^(.*<body[^>]*>)(.*)(</body>.*)"
    return head .. s .. tail
  end;

  SetTitle = function(_ENV,title)
    local TITLE = "%$TITLE%$"
    document = document:gsub(TITLE,title)
  end;

  Span = function(s,class)
    return ("<span class=%s>%s</span>"):format(class,s)
  end

}

local markups = {plain=plain, html=html, markdown=markdown}

local function toSAF(object,...)
  if object and object.toSAF then return object:toSAF(...) end
end

DATE.toSAF = function(date,options)
  options = default:setoptions(options)
  if not date._year then date:_init() end
  local day,       month,       year,       status = 
  date._day, date._month, date._year, date._status
  local dat = {}
  if status then append(dat,options[status]) end
assert(type(day)~='string',day)
assert(type(month)~='string',month)
assert(type(year)~='string',year)
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
  local color = html.Green
  if not event.PLAC and not event.DATE then color = html.Red end
if options.critic and not event.PLAC then append(ev,color("Waar?")) end
  append(ev,event.PLAC and event.PLAC:toSAF(options))
if options.critic and not event.DATE then append(ev,color("Wanneer?")) end
  append(ev,event.DATE and event.DATE:toSAF(options))
  append(ev,event.NOTE and event.NOTE:toSAF(options))
  if #ev>1 then return tconcat(ev," ") end   
end

NOTE.toSAF = function(note,options)
  local markup = markups[options.markup]
  if not nonblank(note.data) then return end  
  local data = note.data:match"^[^\n]*" -- only first line used
--  if note.prev and note.prev.tag == 'INDI' then 
--    data = "("..data..")"     -- put parentheses around a personal note
--  end
  return markup.Emph(data)
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
  detail = detail or LIFESPAN
  local markup = markups[options.markup]
  local omit_surname = (detail & SURNAME) == 0
  local ind = {}
  local name = indi:name{capitalize=options.capitalize,
    omit_surname=omit_surname,nickname='"%s"'}:gsub("Anonymous","Pn")
  if not options.weak then name = markup.Strong(name) end
  append(ind,name)
--  append(ind,indi:nickname(options))
  if (detail & LIFESPAN) > 0 then
    local lifespan = indi:lifespan()
if options.critic and not lifespan then append(ind,markup.Red"Datums?") end
    append(ind,lifespan)
    ind = {tconcat(ind," ")}
--    append(ind,toSAF(indi.NOTE,options))
  elseif (detail & EVENTS) > 0 then
if options.critic and not indi.BIRT then append(ind,markup.Red"Gebore?") end
    append(ind,toSAF(indi.BIRT,options))
    append(ind,toSAF(indi.CHR,options))
if options.critic and not indi.DEAT and indi:birthyear() and 
  indi:birthyear()<1920 then append(ind,markup.Red"Oorlede?") end
    append(ind,toSAF(indi.OCCU,options))
    append(ind,toSAF(indi.RESI,options))
    append(ind,toSAF(indi.DEAT,options))
    append(ind,toSAF(indi.BURI,options))
  end
  ind = tconcat(ind,options.indi_sep)
  local father, mother = indi:father(true), indi:mother(true)
  if (detail & PARENTS) > 0 then
    local co = options.child_of
    if indi:female() then co = options.daughter_of
    elseif indi:male() then co = options.son_of
    elseif options.critic then append(ind,Red"Geslag?")
    end
    local par = {}
if options.critic and not father then append(par,markup.Red"Vader?") end
    append(par,toSAF(father,LIFESPAN|SURNAME,
      {weak=true,note=", "},false))
if options.critic and not mother then append(par,markup.Red"Moeder?") end
    append(par,toSAF(mother,LIFESPAN|SURNAME,
      {weak=true,note=", "},false))
    if father or mother or options.critic then
      ind = tconcat({ind, tconcat(par,options.AND)},
              options.co_sep..' '..co..' ')    
    end
  end
  local note = toSAF(indi.NOTE,options)
  if note then 
    return ind .. options.note .. note .. options.note
  else
    return ind
  end
end

local GISAprefix = function(prefix,markup)  
  return ("%s %s%s"):format(
    markup.abbrDeV(prefix:match"%l%d+$"),
    markup.fullDeV(prefix),
    markup.Tab or '')
end

--- indi:toSAFtree(prefix,options)
-- prefix: the De Villiers code of this person, e.g. b2c3d7
INDI.toSAFtree = function(indi,options,prefix)
  options = default:setoptions(options)
  local markup = markups[options.markup]
  local detail 
  local class
  local tree = {}
  local fprefix, generation
  if prefix then --- this is a descendant
    detail = EVENTS
    fprefix = GISAprefix(prefix,markup)
    generation = prefix:match"(%l)%d+$"    
    generation = string.char(generation:byte()+1)
  else --- this is the stamvader
    class="stamvader"
    detail = EVENTS | SURNAME | PARENTS
    fprefix = ''
    prefix = ''
    generation = options.prefix or 'b'
  end
  append(tree,fprefix..indi:toSAF(detail,options))
  for spouse,fam,k in indi:spouses() do
    local marriage = fam.MARR
    if marriage then
      marriage = marriage:toSAF(options)
    end
    if marriage then marriage = options.MARR:rep(k-1)..marriage
    else marriage = options.MARR:rep(k) 
    end
    if class ~= "stamvader" then marriage = markup.Tab..marriage end
    local divorce = fam.DIV 
    if divorce then
      divorce=divorce:toSAF(options)
if not divorce then print(-fam.DIV) end
    end
    if divorce then marriage = marriage.." "..divorce end
    append(tree,marriage..' '..
      spouse:toSAF(EVENTS|PARENTS|SURNAME,options,false))
    local note = toSAF(fam.RESI,options)
    if note then append(tree,note) end
    note = toSAF(fam.NOTE,options)
    if note then append(tree,note) end
  end
  tree = {markup.Person(tconcat(tree,markup.NewLine),class)}
  if indi:male() or not options.maleline then
    for child,j in indi:children() do
      if prefix=='' then
        append(tree,markup.Header(2,generation..j))
      end
      append(tree,markup.Person(child:toSAFtree(options,prefix..generation..j))) 
    end
  end
  return tconcat(tree,options.descendants)
end

--- ged:toSAF(root,options)
-- root: a single INDI or a collection
GEDCOM.toSAF = function(ged,root,options)
  if not root then return end
  options = options or {}
  options = default:setoptions(options)
  if options.html then 
    html.document = options.html
  end
  local markup = markups[options.markup]
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
     append(saf,markup.Header(1,indi:name():upper()))
     append(saf,indi:toSAFtree(options))
  end
  if markup.SetTitle then 
    markup:SetTitle(root[1]:name():upper()) 
  end
  return markup.Wrap(tconcat(saf,markup.Page)), msg
end

--- Take a typical GISA .docx, export it as HTML by e.g. Libreoffice Writer. 
-- The contents of <body>...</body> and <title>...</title> will be replaced.
html.document = [[
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8"/>
	<title>$TITLE$</title>
	<style type="text/css">
		@page { margin-left: 1cm; margin-right: 1cm; margin-top: 1cm; margin-bottom: 1.91cm }
		p { margin-left: 1.27cm; text-indent: -1.27cm; margin-bottom: 0.14cm; direction: ltr; line-height: 105%; text-align: left; page-break-inside: avoid; orphans: 2; widows: 2; so-language: af-ZA }
                p { font-family: "Calibri", "Carlito"; font-size: 11pt }
                p.stamvader {  margin-left: 0cm; text-indent: 0cm; }
                b { font-family: "Calibri", "Carlito"; font-size: 11pt }
		h1 { margin-left: 0cm; text-indent: 0cm; margin-top: 0cm; margin-bottom: 0.14cm; direction: ltr; line-height: 105%; text-align: left; page-break-inside: avoid; orphans: 2; widows: 2 }
		h1{ font-family: "Cambria", serif; font-size: 14pt; so-language: af-ZA }
		h2{ font-family: "Calibri", "Carlito"; font-size: 13pt; so-language: af-ZA }
                .blind { font-family: "serif"; color: #ffffff; font-size: 1pt; margin-right: 0.87cm}
	</style>
</head>
<body lang="af-ZA" dir="ltr">
$BODY$
</body>
</html>
]]

local edit = {
province_required = "Middelburg,Heidelberg",
delete_country = "South Africa,Suid-Afrika,Suid Afrika",
delete_province = "Cape Province,Kaapprovinsie,Natal,Transvaal,Oranje-Vrystaat"
  ..",Cape Colony,Cape of Good Hope,Orange Free State,OFS"
  ..",Free State,Vrystaat,Gauteng,Western Cape"
}
for k,csv in pairs(edit) do
  local list = {}
  for place in csv:gmatch"[^,]+" do
    list[#list+1]=place
    list[place] = true
  end
  edit[k] = list
end

local translate = [[
district=distrik
Argentina=Argentinië
Cape Town=Kaapstad
Diep River=Dieprivier
East London=Oos-Londen
England=Engeland
Fish Hoek=Vishoek
Germany=Duitsland
India=Indië
Mission=Sendingstasie
New Zealand=Nieu-Seeland
Northern =Noord-
Nyasaland=Njassaland
Piquetberg=Piketberg
Southern =Suid-
Rhodesia=Rhodesië
Three Anchor Bay=Drieankerbaai
Victoria Hospital=Victoria-hospitaal
 West=-Wes
]]
    do local t = {}
for source,target in translate:gmatch"([^=]+)=([^\n]+)\n?" do
  t[source] = target
end
translate = t
    end

PLAC.toSAF = function(place,options)
  if not nonblank(place.data) then return end
  local required=edit.province_required
  place = place.data
  for country in pairs(edit.delete_country) do
    place = place:gsub(",%s*%[?"..country.."%]?","")
  end  
  for _,province in ipairs(edit.delete_province) do 
    if not required[province] then
      place = place:gsub(",%s*"..province,"")
    end
  end  
  for source,target in pairs(translate) do
    place = place:gsub(source,target)
  end
  return place
end

default.edit = edit
default.translate = translate



