--- template.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Functions involving GEDCOM templates.

-- See 'gedcom.lua' for the documentation of GEDCOM objects. This module
--    extends functionality by adding methods to the GEDCOM table.

------------------------------- Templates ------------------------------

--- GEDCOM templates.
--
--  A template is a description of what is allowed at a particular point
--  in a GEDCOM file. It may be of five possible types.
--   table     Keys are tags, values are templates. The [1] entry, if any, 
--             is applied to the main record, and must not be a table; the
--             other entries in the template are applied to those subrecords 
--             that have the specified tag.
--   boolean   If true, the object is unconditionally OK; if `false`, the 
--             tag is explicitly disallowed at that position.
--   nil       The object is ignored and a warning message is issued.
--   string    A pattern against which `data` must matched.
--   function  The function is evaluated with the object as argument.
--             If true, the object is OK. If false, there must be a second 
--             return value giving a message why the object is not OK. 
--             The message may contain %s, which will be replaced by the
--             fully qualified tag of the object.
--  The non-table values all imply that subrecords are not to be validated.
--  If you want that too, put the template in the [1] entry of a table.
--
-- Supplied predefined scalar templates. These all return nil,message
-- on failure; below is shown what they return on success.
--  has_key       key in definition
--  parse_date   year, month, day as numbers
--  name_pattern  surname
--  key_pattern   key referred to in data

local gedcom = require "gedcom.gedcom"

local glob, meta, util = gedcom.glob, gedcom.meta, gedcom.util
local GEDCOM, RECORD, FIELD, ITEM = 
  meta.GEDCOM, meta.RECORD, meta.FIELD, meta.ITEM
local Message = util.Message 
local lineno, tags, parse_date = glob.lineno, glob.tags, glob.date

local event = {
  DATE = parse_date,
  PLAC = true
} 

local description = {}
local key_pattern = '^@(.+)@$'
local name_pattern = '^[^/]*/([^/]+)/[^/]*$'
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
FIELD.validate = GEDCOM.validate
ITEM.validate = GEDCOM.validate

---------------------------- end of Templates --------------------------

