--- template.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Functions involving GEDCOM templates.
-- See 'gedcom.lua' for the documentation of GEDCOM objects. This module
--    extends functionality by adding methods to the GEDCOM table.
-- BUGS
-- - Can only append records to a parent; can't insert or delete them.

--[[ ----------------------------- Templates ------------------------------

A GEDCOM template is a table constructed so that it can be indexed in the same 
the way that (thanks to metatable magic) GEDCOM records are, e.g.

  { NAME = 'Robert Naylor /LAURIE/',
      BIRT = {
        PLAC = 'Ahmednuggur, India',
        DATE = '9 Aug 1823' };
      DEAT = {
        PLAC = 'Lyttelton, New Zealand',
        DATE = '21 Jul 1859' };
      NOTE = 'Lived at the Cape of Good Hope 1850-1858 and founded a family'
  }

This example shows a template being used as an alternative representation for
a GEDCOM record: the values are again tables or ultimately strings. It is
convenient when there is only one field with a specific tag. 

A template can also be used to specify a particular GEDCOM dialect, give 
actions to be performed when a GEDCOM container is traversed, etc. Examples
are given when the application is defined.

--]]

local gedcom = require "gedcom.gedcom"
require "gedcom.lifelines"

local glob, meta, util = gedcom.glob, gedcom.meta, gedcom.util
local GEDCOM, RECORD, INDI, FAM, DATE, NAME = 
  meta.GEDCOM, meta.RECORD, meta.INDI, meta.FAM, meta.DATE, meta.NAME
local name_pattern = util.name_pattern
local Message = util.Message 
local lineno, tags, parse_date = glob.lineno, glob.tags, glob.date
local tconcat, append = table.concat, table.insert

local key_pattern = '^@(.+)@$'
local key_format = '@%s@'
local name_pattern = '^[^/]*/([^/]+)/[^/]*$'
local date_format = "%04d"
local spouse_code="^x+$"
local child_code="^b%d+$"

local Error, Warning = true, false

--- nonblank(s) is s if s is a non-blank string, otherwise false
local function nonblank(s)
  return type(s)=='string' and s:match"%S" and s
end

-- print key-value pairs of table with key matching pattern
local choose = function(tbl,pattern)
  local choose={}
  for k,v in pairs(tbl) do
    if type(k)~='string' then print("Nonstring key "..tostring(k),k,v) end
    if type(k)=='string' and k:match(pattern) then
      append(choose,("%s=%s"):format(k,v))
    end
  end
  return '{'..tconcat(choose,", ")..'}'
end

--[[ APPLICATION: creating a template from SAF person data ]]

    do 
local particles = "VAN DE DER LA LE DU DA TE"
local particle = {}
for word in particles:gmatch"%S+" do particle[word]=true end
NAME.fromSAF = function(saf)
  local words = {}
  for word in saf:gmatch"%S+" do
    if particles[word] then append(words,word:lower())
    else append(words,word:sub(1,1)..word:gsub(".(.*)",string.lower))
    end
  end
  return tconcat(words,' ')
end
    end -- closure of NAME.fromSAF

    do
local toGEDCOM = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct",
  "Nov","Dec"}
DATE.fromSAF = function(saf)
  local day,month,year = saf:match"(%d?%d?)%.?(%d?%d?)%.?(%d%d%d%d)"
  if day:match"%S" then
    return day.." "..toGEDCOM[tonumber(month)].." "..year
  end
end
   end -- closure of DATE.fromSAF

    do
local evtype = {['*']="BIRT",["~"]="CHR",["%"]="DIV",["+"]="DEAT",
  ["#"]="BURI"}
--- Convert an individual record from SAF text notation to a GEDCOM template,
-- e.g. the template given above corresponds to
-- "Robert Naylor LAURIE * Ahmednuggur, India 09.08.1823 + Lyttelton, New Zealand 21.07.1859. Lived at the Cape of Good Hope 1850-1858 and founded a family"
INDI.fromSAF = function(saf)
-- ASCII substitutes for multibyte symbols
  local tp = {}
  saf = saf:gsub("†","+"):gsub("≈","~"):gsub("÷","%"); 
-- one clause
  local function fromSAF(clause)
    local datestart, date, datestop = 
      clause:match"()(%d?%d?%.?%d?%d?%.?%d%d%d%d)()"
    local pre, name, post = 
      clause:match"()(%u[ %u]*%u)()"
    if date then -- This is an event. There may be a place before and a note
                 -- after. The note after may be preceded by a period, in
                 -- which case the note belongs to the record, otherwise it
                 -- belongs to the event. 
      local evt,place = clause:sub(1,datestart-1):match"([*~+%#])%s+(.*)"
      local note,term,endnote = clause:sub(datestop):match"([^.]*)(%.?)%s*(.*)"
      evt = evtype[evt]
      tp[evt] = {DATE=DATE.fromSAF(date),PLAC=place,NOTE=nonblank(note)}
      tp.NOTE = tp.NOTE or nonblank(endnote)
    elseif name then  -- This is a name.
      pre, post = clause:sub(1,pre-1), clause:sub(post)
      name = NAME.fromSAF(name)
      tp.NAME = pre.."/"..name.."/"..post
    else
      print(clause)
    end
  end
  local start = 1
  for stop in saf:gmatch" ()[*~+%#]" do
    fromSAF(saf:sub(start,stop-1))
    start = stop   
  end
  fromSAF(saf:sub(start,#saf))
  return tp
end
   end -- closure of INDI.fromSAF

--[[ APPLICATION: updating a GEDCOM file ]]

-- Prepare a table (called a 'journal') of GEDCOM templates (called 'entries').
-- Then call 'ged:update(journal)'.
--
-- The journal also has fields 'surname', which is used as a default when only
-- forenames are supplied, and 'source', which must be equal to the value in 
-- the HEAD.SOUR field of GEDCOMs written by a particular source.
--
-- Each entry is identified on one or more of the fields 'name', 'key' and
-- 'WWW'.

local newkey

   do
local last = {}
newkey = function(letter,lookup)
  local n = (last[letter] or 1000) + 1
  while lookup[letter..n] do n=n+1 end
  last[letter] = n
  return letter..n
end
  end  

local fix_gedcom = { 
  ["WikiTree.com"] = function(ged)
    msg = ged.msg
    msg:append"Fixing WikiTree GEDCOM: moving biographies into level 0 records"
    for indi in ged:tagged"INDI" do
      local note = indi.NOTE
      local data = note and note.data
      if data and data:match"%S" then
        local keynote = "N"..indi.key
        ged:append(RECORD.new(keynote,"NOTE",data))
        note:to""
      end
    end  
  end
}

FAM.husbandname = function(fam)
  local husband = fam:husband()
  return husband and husband:name()
end

FAM.wifename = function(fam)
  local wife = fam:wife()
  return wife and wife:name()
end

--- ged:identify(entry)
-- If 'entry' describes a unique individual or family, that is the result.
-- Otherwise returns nil and the list of matches.
GEDCOM.identify = function(ged,entry)
  local list 
  if entry.name or entry.lifespan then 
    list = ged:find{name=entry.name,key=entry.key,
      lifespan=entry.lifespan,WWW=entry.WWW}
  elseif entry.husband or entry.wife then
    local couple = {entry.husband}   -- can't remember why this is in
    couple[#couple+1] = entry.wife   -- but maybe it will be useful
    list = ged:find{husbandname=entry.husband,wifename=entry.wife,
      key=entry.key,WWW=entry.WWW}
  end
  if list and #list == 1 then return list[1]
  else return nil, list
  end
end

GEDCOM.update = function(ged,journal)
  journal.source = journal.source or 
    ged.HEAD and ged.HEAD.SOUR and ged.HEAD.SOUR.data
  if not journal.source then
    print"Die bron van die GEDCOM kon nie vasgestel word nie."
    journal.source = "Onbekend"
  end
  local fix = fix_gedcom[journal.source]
  local msg = ged.msg
  if fix then
    fix(ged) 
  elseif journal.source then
    print("Daar bestaan nog nie 'n leser vir "..journal.source..
    " se idiolek van GEDCOM nie.\nParty velde word dalk nie benut nie.")
  end
  local CONTINUE=true
  local list 
  for k,entry in ipairs(journal) do repeat  -- break == continue
    for key in pairs(entry) do if type(key)~='string' then 
      print("Nonstring key "..tostring(key).." in entry "..k) 
    end end
    local descr = choose(entry,"^%l+$")
    if entry.name or entry.lifespan then 
      entry.surname = journal.surname 
    end
    local record,list = ged:identify(entry)
    if not record then
      print(#list.." matching entries for query "..descr)
      for k,v in ipairs(list) do print(v.key,v:refname()) end
      print"!!! Skipping this update record"
      break
    end
    msg:append("Updating entry for %s %s",record.key,record:refname())
    record:update(entry,ged)
  until CONTINUE
  end
end

   do local allowed = {name=true, surname=true, husband=true, wife=true,
        lifespan=true}
RECORD.update = function(record,entry,ged)
  assert(type(record)=='table',[[assertion "type(record)=='table'" failed!]])
  local msg = record.msg or Message()
  for tag,value in pairs(entry) do 
    if tag==1 then
      record:to(value)
    elseif type(tag)~='string' then
      msg:append(Error,"Can't handle tag %s in %s",tag,record.key)
    elseif tag==tag:upper() then
      local field = record[tag]
      if not field then 
        field = RECORD.new(nil,tag,'')
        record[tag] = field
        record:append(field)
      end
      if type(value)=='string' then
        field:to(value)
      elseif type(value)=='table' then 
        field:update(value)
      end
    elseif record.tag=='INDI' and tag:match(spouse_code) then
      local relative = ged:newrelative(record,value,tag,
        surname or record:surname())
      ged:append(relative)
      ged:append(record:newfamily(relative,tag))
    elseif record.tag=='FAM' then
      local relative = ged:identify(value)
      if tag:match(child_code) then
        if not relative then
          relative = ged:newrelative(record,value,tag,
          surname or record:surname())
        end
        ged:append(relative)
        record:newchild(relative)
      elseif tag:match(spouse_code) then 
        local oldspouse, newspouse, husband, wife
        husband, wife = record:husband(), record:wife()
        if husband and wife then
          msg:append(Error,"Can't add a third spouse to an existing family")
        else
          oldspouse = husband or wife
        end
        newspouse = relative 
        if not newspouse then
          newspouse = ged:newrelative(record,value,tag)
          ged:append(newspouse)
        end
        record:addspouse(oldspouse,newspouse)    
      end
    elseif not allowed[tag] then
      msg:append(Error,"Can't handle tag %s in %s",tag,record.key)
    end 
  end
end
    end  -- closure for RECORD.update

--[[
RECORD.assign = function(record,tag,data)
print(tag)
  local top,tail = tag:match"([^.]+)%.(.*)"
  if not top then
    record[tag]:to(data)
  else
    record[top]:assign(tail,data)
  end
end
--]]

GEDCOM.newrelative = function(ged,indi,entry,tag,surname)
  local msg = indi.msg or Message()
  local name = entry.NAME
  local name_is_table = type(name)=="table"
  if name_is_table then name=name[1] end
  if not name then
    msg:append(Error,"New relative %s in update journal for %s has no NAME",
      tag,surname)
    return
  end
  if not name:match(name_pattern) then 
    if tag:match(spouse_code) then
      msg:append(Error,"New spouse %s has name %s but no surname",
        tag,name)
      return
    else
      name = name .. " /" .. surname .. "/"
      if name_is_table then entry.NAME[1] = name
      else entry.NAME = name 
      end
    end
  end  
  local rec = RECORD.new(newkey("I",ged.INDI),"INDI")
  rec:update(entry,ged)
  if not rec.SEX then
    msg:append(Warning,"No SEX specified for %s",rec:refname())
  end
  if not rec:birthyear() then
    rec:update{BIRT={DATE=fyear}}
  end
--[[
    local year = tag:match"%d+"
    if year then
      fyear = date_format:format(year)
      msg:append(Warning,
        "Spurious birth year %s has been allocated to %s",
        fyear,rec:name(true))
      rec:update{BIRT={DATE=fyear}}
    else
      msg:append("Can't extract a number from ",tag)
    end
--]]
  msg:append("Created new %s %s %s for %s",rec.tag,rec.key,name,indi.key)
  return rec
end 

FAM.addspouse = function(fam,indi,spouse)
  local role, partner
  if indi.SEX.data:match"M" then role, partner = 'HUSB', 'WIFE'
    else role, partner = 'WIFE', 'HUSB'
  end
  fam:append(RECORD.new(nil,role,key_format:format(indi.key)))
  fam:append(RECORD.new(nil,partner,key_format:format(spouse.key)))  
end

INDI.newfamily = function(indi,spouse)
  msg:append("Creating new family %s x %s",indi:name(),spouse:name())
  local key = newkey("F",ged.FAM,"")
  local fam = RECORD.new(key,"FAM")
  indi:append(RECORD.new(nil,"FAMS",key_format:format(key)))
  spouse:append(RECORD.new(nil,"FAMS",key_format:format(key)))
  fam.MARR = spouse.MARR
  spouse.MARR = nil
  fam:addspouse(indi,spouse)
  return fam
end

FAM.newchild = function(fam,child)
  child:append(RECORD.new(nil,'FAMC',key_format:format(fam.key)))
  fam:append(RECORD.new(nil,'CHIL',key_format:format(child.key)))
end

--[[ APPLICATION: validation of a GEDCOM file

A line in GEDCOM file can be tested, allowed, forbidden or ignored. This is
specified by terminals, i.e. values in a GEDCOM template of any type but 
'table'. 

    `nil`       Ignored
    `false`     Forbidden
    `true`      Allowed
    pattern     The 'data' value of the field is matched against the pattern.
                If the match succeeds, the record is allowed, otherwise it is
                forbidden.
    func        The function is called with the field as argument. It must
                return `nil`, `false` or `allowed` as above. 

In addition to fields at named keys, there may also be a terminal at the [1]
entry of a record. If this is a pattern or function, the test is made using
the record itself.
--
-- Supplied predefined scalar templates. These all return nil,message
-- on failure; below is shown what they return on success.
--  has_key       key in definition
--  parse_date   year, month, day as numbers
--  name_pattern  surname
--  key_pattern   key referred to in data

--]]

local event = {
  DATE = parse_date,
  PLAC = true
} 

local description = {}
description[key_pattern] = "pattern for a key: " -- ..key_pattern
description[name_pattern] = "pattern for a name: " -- ..name_pattern
local Warning,Error = false,true

--- returns a function that tests whether a word is one of those
-- in a given list
local any_of = function(list)
  local words = {}
  list:gsub("%S+",function(w) words[w]=true end)
  return function(data)
    if type(data)=='table' then data = data.data end
    assert(data,"nil data supplied to any_of")
    if words[data] then return data
    else return nil,"%s is not in %s",data,list
    end
  end
end

local has_key = function(record)
  assert(tags(record),"has_key takes a table with a 'tags' field")
  if record.key then return record.key
  else return Warning, "Tag %s must have a key",tags(record)
  end
end  

--- default template, whitelist and synonyms go into the GEDCOM table
-- and are retrieved automatically by __index. May be shadowed by your
-- own fields.

GEDCOM.template = {
  HEAD = { true,
    CHAR = any_of'ANSI ANSEL UTF-8',
    DATE = parse_date,
    DEST = true,
    SUBM = true,
    FILE = true,
    GEDC = true,
    };
  INDI = { 
    NAME = { name_pattern,
      NICK = true };
    SEX = any_of'M F N',
    BIRT = event,
    DEAT = event,
    CHR = event,
    BURI = event,
    FAMC = key_pattern,
    FAMS = key_pattern,
    };
  FAM = { 
    HUSB = key_pattern,
    WIFE = key_pattern,
    CHIL = key_pattern,
    MARR = event,
    DIV = event,
  };
  NOTE = has_key;
  SOUR = has_key;
  SUBM = has_key;
  REFN = false;
  RFN = false;
  TRLR = true
}

GEDCOM.whitelist = "NOTE RFN REFN SOUR CHAN"
GEDCOM.synonyms = {CHRA = "CHR"}
      
--- gedcom:validate(template)
-- Checks that the given GEDCOM container conforms to the specification
-- in the template, and that all keys referred to are defined
GEDCOM.validate = function(gedcom,template,whitelist,synonyms)
  template = template or gedcom.template
  whitelist = whitelist or gedcom.whitelist
  synonyms = synonyms or gedcom.synonyms
  local whitelisted = any_of(whitelist)
  local msg = Message()
  local function report(pos,fmt,...)
    msg:append(Warning,pos,fmt,...)
  end
--- check that cross-references are satisfied
  local function _checkref(ged,main)
    main = main or ged
    if ged.data then
    local key = ged.data:match(key_pattern)
      if key and not main[key] then
        report("key %s is used but nowhere defined",key) 
      end
    end
    for _,record in ipairs(ged) do
     _checkref(record,main)
    end
  end
  local function validate (ged,tmpl)
    if ged == nil then return end
    local pos = lineno(ged)
-- Tests that do not examine `ged`
    if tmpl==nil and pos then
      return whitelisted(ged.tag) or
        report(pos,'Tag %s ignored and its subrecords skipped',tags(ged))
    elseif not tmpl then
      report(pos,"%s is not allowed here",ged.tag)
    elseif tmpl==true then 
      return  -- nothing to test, always OK
    end
-- At level 0, if not marked `true`, there must be a key
    if tmpl==nil and ged.prev==gedcom then
      local OK,errmsg = has_key(ged) 
      if not OK then report(pos,select(2,has_key(ged))) end
    end
    if type(tmpl) == 'function' then
      local OK,errmsg = tmpl(ged)
      return OK or report(pos,select(2,tmpl(ged)))
    elseif type(tmpl)=='string' then
      return ged.data:match(tmpl) or
        report(pos,"Data does not match %s%s",description[tmpl],ged.data)
    elseif type(tmpl)=='table' then
      if tmpl[1] then
        assert(type(tmpl[1])~='table','template[1] may not be a table')
        validate(ged,tmpl[1])
      end
      for _,record in ipairs(ged) do
         validate(record,tmpl[record.tag] or tmpl[synonyms[record.tag]])
      end
    else 
      assert(false,"A template item may not be of type "..type(tmpl))     
    end
  end            
  validate(gedcom,template)
  _checkref(gedcom)
  return msg
end

RECORD.validate = GEDCOM.validate


