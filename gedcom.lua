--- gedcom.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Object-oriented representation of GEDCOM files
-- Lua Version: 5.3 (uses the `utf8` library)

assert (utf8 and string and table 
    and string.unpack and utf8.len and table.move, 
    "The module `gedcom` needs Lua 5.3")
-- Note on `assert`: it is used to detect programming errors only.
-- Errors in the GEDCOM file are reported in a different way.

-- The module returns a table with fields: `read, help, util, glob, meta`.
local help = [[
The module returns a table, here called `gedcom`, containing:
  `help` This help string.
  `read` A function which constructs a GEDCOM container, here called `ged`, 
    and in addition returns a message, here called `msg`, suitable for 
    writing to a log file. If construction failed, `ged` is nil and `msg`
    gives the reason for failure.
  `glob` A few functions that would be convenient additions to the global 
    library.
  `meta` The metatables of GEDCOM-related objects: GEDCOM, RECORD, FIELD, 
    ITEM.
  `util` A table containing utility functions. They are provided mainly 
    for the convenience of code maintainers, and as documented briefly 
    below in LDoc format compatible with the module `ihelp` available 
    from LuaRocks.

`gedcom.read` takes one argument, which must be the name of an existing 
GEDCOM file. Thus you will normally have the following lines in your 
application:

    gedcom = require "gedcom"
    ged, msg = gedcom.read (GEDFILE) 

GEDCOM lines up to level 3 are parsed according to the rule that each line 
must have a level number, may have a key, must have a tag, and must have 
data (but the data may be empty). This is where it stops. At level 4 and 
deeper, only the level number is examined.  

There are five types of GEDCOM-related objects, container, record, field, 
item, subitem. More details on them is available in GEDCOM.help, RECORD.help,
FIELD.help and ITEM.help.

All objects except containers have the following entries:
   `key`: a GEDCOM key located inside at-signs between the level number and 
the tag on a line in the GEDCOM file such as `I1`, `F10` etc. May be nil.
   `tag`: a GEDCOM tag such as INDI, DATE etc.  
   `data`: whatever remains of the line after the tag. May be nil. If present
and non-empty, the first character is not a blank.
   `line`: the original line as read in, except that CONC and CONT lines 
are not kept as separate entities, but have their data appended (in the case
of CONT, joined by a newline) to the data of the main line to which they 
belong. In CONC and CONT lines, 'data' may have leading blanks, i.e. only 
one blank is assumed to separate 'tag' from 'data'. 
   `prev`: the higher-level object to which the object belongs.
   `size`: the number of lines in the original GEDCOM file that the onject
occupies.
   `lineno`: the number of the line in the original GEDCOM file where this
object starts.
   `msg`: a message object. May be nil. See MESSAGE.help.

All types except subitems have an __index metamethod such that you can say 
`ged.HEAD.CHAR.data`, `ged.I1.NAME`, etc. 

Extended indexing is read-only in the sense that you can't replace an 
object. Nothing stops you from assigning a value to e.g. `ged.I1`, but 
that value will shadow the the original record that you retrieved as 
`ged.I1`. If you then assign nil to `ged.I1`, the original will reappear.]]

-- initialize metatables
local GEDCOM = {__name="GEDCOM container"}
local RECORD = {__name="GEDCOM record"}
local FIELD = {__name="GEDCOM field"}
local ITEM = {__name="GEDCOM item"}
local MESSAGE = {__name="GEDCOM message list"}

GEDCOM.help =[[
- A GEDCOM _container_ is a table (metatable GEDCOM) containing GEDCOM 
records at entries 1,2,...,. It does not have the entries that all the 
others have. Instead, it has:

  filename    The name of the GEDCOM file.
  gedfile     The handle of the GEDCOM file.
              byte of the Level 0 line with which that entry starts.
  INDI        A table in which each entry gives the number of the record 
              defining the individual with that key (at signs stripped off).
  FAM         A table in which each entry gives the number of the record
              defining the family with that key (at signs stripped off). 
  OTHER       A table in which each entry gives the number of the record
              defining any other record with that key (at signs stripped off).
  firstrec    A table in which each entry is the number of the first 
              record with that tag (unkeyed records only).
  _INDI       A list of records with tag `INDI` in their original order.
  _FAM        A list of records with tag `FAM` in the original order.
  msg         List of messages associated with processing this GEDCOM.
              In addition, each line may have its own `msg`.

Indexing of a GEDCOM container is extended in the following ways:
  1. Keys. Any key occuring in a Level 0 line can be used, with or without 
     at-signs, as an index into the container. (This is the purpose 
     of INDI, FAM and OTHER.)
  2. Tags. Any tag in an _unkeyed_ Level 0 record can be used as an index
     into the container, and will retrieve the _first_ unkeyed record 
     bearing that tag. 
  3. Methods. Functions stored in the GEDCOM metatable are accessible in
     object-oriented (colon) notation, and all fields stored there are 
     accessible by indexing into the container, except when shadowed.
]]
RECORD.help = [[
A GEDCOM _record_ is a table (metatable `RECORD`) in which `line` contains 
a Level 0 line from a GEDCOM file. It may, at entries 1,2,..., contain 
fields. This is the only type in which `key` is usually not nil.

Indexing of records and lower-level GEDCOM objects is extended as follows:
  1. Tags. Any tag in a field or item can be used as an index into the object, 
     and will retrieve the _first_ record bearing that tag. This access is 
     memoized: there will be a key equal to that tag in the record after the 
     first access.
  2. Methods, as for GEDCOM containers.
  3. Tag-specific methods. Modules using this one may add a key-value pair
     to `gedcom.meta`, in which the key is a GEDCOM tag and the value is
     a table of methods taking records etc with that tag as first argument.
     E.g. methods in `gedcom.meta.INDI` are available to records with tag
     `INDI` but not to other GEDCOM records.]]
FIELD.help = [[
A GEDCOM _field_ is a table (metatable `FIELD`) in which `line` contains 
a Level 1 line from a GEDCOM file. It may, at entries 1,2,..., contain items.]]
ITEM.help = [[
A GEDCOM _item_ is a table (metatable `ITEM`) in which `line` contains a 
Level 2 line from a GEDCOM file. It may, at entries 1,2,..., contain subitems.

A GEDCOM _subitem_ is a table (no metatable) in which `line` contains 
a Level 3 line from a GEDCOM file. It may also have an entry `lines` which 
is an array of strings containing at least one line at level 4 or beyond.]]

-- declare some utilities as upvalues
local append, tconcat, tsort = table.insert, table.concat, table.sort
local util, -- forward declaration of utilities
   Record, reader, level, tagdata, keytagdata, to_gedcom, lineno, tags
-- forward declaration of private methods
local _read, _parse_date 

MESSAGE.help = [[
Customizable messaging. 

Msg = Message(translate) constructs a message processor with a custom 
  translation table, which is stored as `Msg.translate`. If no translation 
  table is given, GEDCOM.translate is used. 

Msg:append ([status,][lineno,]message,...) appends a parameterized message to the 
  processor, constructed as 'message:format(...)'. 
    `status` is an optional boolean argument: if omitted, the message is 
    purely informative; if `true`, it describes an error; if `false`, 
    a warning. Boolean upvalues `Error=true` and `Warning=false` are provided 
    for this file only.
    `lineno` is an optional number argument: if provided, it appears before
    the message.

Default is to print warnings and errors on `io.stderr` and to stop at first 
error. You can raise the tolerated number of errors by assigning a higher 
number to `Msg.errlim` or make it infinite by `Msg.errlim=nil`, which also 
inhibits both these actions for a particular Msg. 

Before being appended, 'message' is replaced by 'translate[message]' if that 
is not nil.

Msg:concat(delim) returns the concatenation of appended messages, using the
specified delimiter (default: newline).]]

local metatable = {[0]=GEDCOM, [1]=RECORD, [2]=FIELD, [3]=ITEM}

--- See MESSAGE.help
local Message = function(translate)
  return setmetatable ( {
    errors = 0,
    warnings = 0,
    errlim = 1,
    rawcount = {},   -- untranslated and unformatted
    count = {},      -- translated and formatted
    translate = translate or GEDCOM.translate or {}
    },
    MESSAGE)
  end
local Error, Warning = true, false
MESSAGE.append = function(msg,...)
  local status, lineno, message = ...
  local tail=4
  if type(status) == 'boolean' then
    if status then msg.errors = msg.errors+1
    else msg.warnings = msg.warnings+1
    end
  else
    lineno, message = status, lineno
    tail = tail-1  
  end
  if type(lineno) ~= 'number' then
    message,lineno = lineno,nil
    tail = tail-1
  end
  if message == nil then return end
  msg.rawcount[message] = (msg.rawcount[message] or 0) + 1
  message = msg.translate[message] or message
  local ok, fmsg = pcall(string.format,message,select(tail,...))
  assert(ok,fmsg)
  local count = (msg.count[fmsg] or 0) + 1
  msg.count[fmsg] = count
  if lineno then fmsg = ("%6d:  %s"):format(lineno,fmsg) end
  append(msg,fmsg)
  if status~=nil then msg:_error(fmsg,count) end
end;
MESSAGE.concat = function (msg,delim)
  return tconcat(msg,delim or "\n")
end 
MESSAGE.__index = MESSAGE
MESSAGE._error = function(msg,message,count)
  if msg.errlim then 
    if count <= 1 then io.stderr:write(message,"\n") end
    if msg.errors >= msg.errlim then
      os.exit()
    end
  end
end

--- lines = assemble(object)  
-- Recursive assembly of a GEDCOM object.
-- Note: `assemble` does not produce valid GEDCOM output, since lines
-- may be longer than 255 characters. That task is performed by `to_gedcom`.
local function assemble(object)
  if type(object)=="string" then return object end
  local buffer = {}
  append({},object.line)  -- allows 
  if object.lines then 
    append(buffer,tconcat(object.lines,"\n"))
  else 
    for k=1,#object do
      append(buffer,assemble(object[k]))
    end
  end
  return tconcat(buffer,"\n")
end

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

-- extract date as three numbers and a modifier
    do
local _status = {AFT="AFT",BEF="BEF",ABT="ABT",EST="EST",CAL="CAL",
   FR="FR",TO="TO"}
local _month = {JAN=1,FEB=2,MAR=3,APR=4,MAY=5,JUN=6,JUL=7,AUG=8,SEP=9,
   OCT=10,NOV=11,DEC=12}
_parse_date = function(data)
  if type(data)=='table' then data = data.data end
  assert(type(data)=='string',
    'Bad argument #1 to _parse_data: expected string, got '..type(data))
  local word = data:gmatch"%S+"
  local status, day, month, year
  local item = word()
  if _status[item] then
    status = item
    item = nil
  end
  item = item or word()
  local n = tonumber(item)
  if n and n>=1 and n<=31 then
    day = n
    item = nil
  end
  item = item or word()
  n = _month[item]
  if n then
    month = n
    item = nil
  end
  item = item or word()
  if item:match"^%d%d%d%d$" then
    year = tonumber(item)
  end
  if year and not (day and not month) and not word() then    
    return year, month, day, status
  else
    return nil,"Nonstandard date format: %s",data
  end  
end  
    end

--- gedcom (FILENAME) constructs a GEDCOM container by reading FILENAME
--          FILENAME='' constructs an empty GEDCOM container
local gedcom = function(filename)
  local gedfile, msg
  if type(filename)~='string' then 
    return nil,"gedcom.read: expected filename, got "..type(filename)
  end
  if filename:match"%S" then 
    gedfile, msg = io.open(filename) 
  end
  if msg and not gedfile then return nil, msg end
  local ged = setmetatable ( {
    filename = filename,
    gedfile = gedfile,
    INDI = {},
    FAM = {},
    OTHER = {},
    _INDI = {},
    _FAM = {},
    firstrec = {}, 
    msg = Message(),  -- a new Message for each container
    },
    GEDCOM)
  if not gedfile then return ged end
  msg = Message()
  if gedfile then msg:append("Reading %s",filename) end
  _read(ged)
  msg:append("%s lines, %s records",ged[#ged].pos,#ged)
  ged.gedfile:close()
  return ged, msg:concat()
end 

-- metamethods of a GEDCOM container

-- The __index metamethod is the Swiss Army knife.
--   ged[k] (retrieved from the GEDCOM file itself)
--   ged.method 
--   ged.I1, ged.F1 etc retrieves keyed record
--   ged.HEAD.CHAR etc at each level is the first tag of that name
GEDCOM.__index = function(ged,idx)
  while type(idx)=='string' do
    idx = idx:match"@(.*)@" or idx  -- strip off at-signs if any  
    local lookup = ged.INDI[idx] or ged.FAM[idx] or ged.OTHER[idx] or
      ged.firstrec[idx]
    if lookup then   -- found in one of the indexes
      return rawget(ged,lookup)  
    end
-- must be a method
    return GEDCOM[idx] 
  end
  assert(type(idx)=='number',"Invalid key type for GEDCOM container: "..type(idx))
end

-- private methods of a GEDCOM container

--- Read entire GEDCOM file into a GEDCOM container
_read = function(ged)
  local gedfile, msg = ged.gedfile, ged.msg
  local rdr = reader(gedfile)
  local firstrec = ged.firstrec
  local k=0
  repeat
    local rec = Record(rdr,0,ged)
    if not rec then break end
    k = k + 1
    local key, tag = rec.key, rec.tag
    if key and tag then
      (ged[tag] or ged.OTHER)[key] = k
      if ged[tag] then  -- update _INDI, _FAM
        append(ged["_"..tag],rec)
      end
    end
    if tag and not key then
      firstrec[tag] = firstrec[tag] or k
    end
    ged[k] = rec
  until false
end  

--- public methods of a GEDCOM container

--- write GEDCOM container to a file
-- ged:write(filename,options)
GEDCOM.write = function(ged,filename,options)
  options = options or {linelength=128}
  local file,errmsg = io.open(filename,"w")  
  if not file then
    ged.msg:append(Error,errmsg)
    return file,msg
  end
  ged:to_gedcom(file,options)
  file:close()
end

--- write GEDCOM object to a file
GEDCOM.to_gedcom = function(object,file,options)
  to_gedcom(file,object.line,options)
  for _,record in ipairs(object) do
    record:to_gedcom(file,options)
  end
end

--- build an index of records keyed by a specified tag. 
--     [index,msg] = ged:build(tag[,stringkey[,msg]])
--  `msg` is a message processor.
--  A second occurrence of the same key is discarded with a warning.
--  If 'stringkey' is omitted, you will get
--     index[record[tag].data] = record
--  'stringkey' must be a Lua expression that evaluates to a string when
--  the global environment is `record[tag]`. The expression will normally
--     involve 'data', e.g. "data" gives the default behaviour.
--  Examples:
--    ged:build "NAME" or ged:build ("NAME","data") uses `NAME.data` as key.
--    ged:build ("BIRT","DATE.data") uses `BIRT.DATE.data` as key.
GEDCOM.build = function(ged,tag,stringkey)
  local msg = Message()
  local index = {}
  local success
  for lno,record in ipairs(ged) do
    local key = record[tag]
    if not key then goto continue end
    local eval = load("return "..(stringkey or "data"),nil,nil,key)
    if not eval then
      msg:append(Error,"Could not compile expression '"..tostring(stringkey).."'") 
      return nil,msg
    end
    success, key = pcall(eval)
    if success then
      if type(key) ~= "string" then
        msg:append(Error,"eval ".." did not return a string")
        goto continue
      end
      if index[key] then
        msg:append(Warning,lineno(record),("Duplicate value for %s: %s"):
          format(tag,index[key].key,record.key))
      else 
        index[key] = record
      end
    elseif key then
      local err = key .. "\n  The above message will be ignored if repeated."
      if err ~= msg[#msg] then msg:append(Warning,err) end
    end
::continue::
  end
  return index,msg
end 

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
--  _parse_date   year, month, day as numbers
--  name_pattern  surname
--  key_pattern   key referred to in data

    do

local event = {
  DATE = _parse_date,
  PLAC = true
} 

local description = {}
local key_pattern = '^@(.+)@$'
local name_pattern = '^[^/]*/([^/]+)/[^/]*$'
description[key_pattern] = "pattern for a key: " -- ..key_pattern
description[name_pattern] = "pattern for a name: " -- ..name_pattern

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
    DATE = _parse_date,
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
-- in the template and that all keys referred to are defined.
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
  local function _checkref(ged)
    if ged.data then
      local key = ged.data:match(key_pattern)
      if not ged[key] then
        report("key %s is used but nowhere defined") 
      end
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
    end

RECORD.validate = GEDCOM.validate
FIELD.validate = GEDCOM.validate
ITEM.validate = GEDCOM.validate

--------------------

--- object, message = Record(rdr,base)
--  Reads one GEDCOM object at level `base`, getting its input from the
--  reader `rdr` (see `reader`). One return value may be nil, but not both.
--    record = Record(rdr,0)
--    field = Record(rdr,1,record)
--    item = Record(rdr,2,field)
--    subitem = Record(rdr,3,item)
Record = function(rdr,base,prev)
  assert(base<=3,"No subdivision supported past level 3")
  local msg={append=append}
  local line,pos,count,key,tag,data
  repeat
    line,pos,count = rdr()
    if not line then return end
    if level(line)~=base then
      msg:append("ERROR in GEDCOM input at position "..pos) 
      msg:append("  -- Expected line at level "..base..", got "..line)
    end
    key, tag, data = keytagdata(line)
    if not key then tag, data = tagdata(line) end
    local conc
    if tag=="CONC" then conc=""
    elseif tag=="CONT" then conc="\n"
    end
    if conc then
      if prev and prev.data and prev.line then
        prev.data = (prev.data or "") .. conc .. data
        prev.line = prev.line .. conc .. data
      else
        msg:append("ERROR in GEDCOM input at position "..pos)
        msg:append("  -- CONC or CONT record at level "..base.."ignored ")
      end
      line = nil
    else  -- strip leading blanks from non-continuation data
      data = data and data:match"^%s*(.*)"
    end  
  until line
  local lines = {}
  local record = setmetatable( {line=line,lines=lines,pos=pos,key=key,tag=tag,
     data=data,msg=msg,prev=prev,size=1,count=count}, metatable[base+1]) 
  for line, pos, count in rdr do
    local lev = tonumber(line:match"%s*%S+") 
    if lev<=base then
      rdr:reread(line)
      break
    end
    append(lines,line)
    record.size = record.size+1
  end
  if #lines>0 and base<3 then 
    local subrdr = reader(lines)
    repeat
      local subrec = Record(subrdr,base+1,record)
      record[#record+1] = subrec
    until not subrec
  end
  if #lines==0 or base<3 then record.lines = nil end
  if #msg==0 then record.msg = nil end   -- delete empty messages
  return record
end

--- RECORD, FIELD and ITEM methods

RECORD.__index = function(record,idx)
-- if it isn't there, it isn't there
  if type(idx)=='number' then return nil end
-- is it a metamethod?
  local metamethod = getmetatable(record)[idx]
  if metamethod then return metamethod end
-- is there a specialized method for this type of record?
  local methods = meta[record.tag]
  local method = methods and methods[idx]
  if method then return method end
-- find the first field with that tag
  for k,field in ipairs(record) do
    if field.tag==idx then
      rawset(record,idx,field)  -- memoize it
      return field
    end
  end
end

RECORD.to_gedcom = GEDCOM.to_gedcom
FIELD.to_gedcom = GEDCOM.to_gedcom

ITEM.to_gedcom = function(item,file,options)
  to_gedcom(file,item.line,options)
  for _,subitem in ipairs(item) do
    to_gedcom(file,subitem.line,options)
    if subitem.lines then 
      for _,line in ipairs(subitem.lines) do
        to_gedcom(file,line,options)
      end
    end   
  end
end

FIELD.__index = RECORD.__index
ITEM.__index = RECORD.__index

ITEM._tags = function(item)
  return item.prev:_tags() .. "." .. item.tag
end

FIELD._tags = ITEM._tags
RECORD._tags = function(record)
  return record.tag
end

RECORD._lineno = function(record)
  return record.count
end

FIELD._lineno = function(field)
  return field.prev:_lineno() + field.count
end

ITEM._lineno = FIELD._lineno

--- non-method `lineno` that works at all levels
lineno = function(subitem)
  if subitem._lineno then return subitem:_lineno()
  elseif subitem.prev then 
    return subitem.prev:_lineno() + subitem.count
  else return subitem.count
  end
end

--- non-method `tags` that works at all levels
tags = function(subitem)
  if subitem._tags then return subitem:_tags()
  elseif subitem.prev then 
    return subitem.prev:_tags() .. subitem.tag
  else return subitem.tag
  end
end

--- Undocumented feature: `-ged.HEAD` etc puts together a record, etc.
RECORD.__unm = assemble
FIELD.__unm = assemble
ITEM.__unm = assemble
MESSAGE.__unm = assemble

--- define forward-declared utilities

--- lvl = level(line); may return nil if input invalid
level = function(line)
  assert(type(line)=="string")
  return tonumber(line:match"%s*(%d+)%s%S")
end

--- tag, data = tagdata(line); may return nils if input invalid
tagdata = function(line)
  assert(type(line)=="string")
  return line:match"%s*%d+%s+(%S+)%s?(.*)"
end

--- key, tag, data = keytagdata(line); may return nils if input invalid
keytagdata = function(line)
  assert(type(line)=="string")
  return line:match"%s*%d+%s+@(%S+)@%s+(%S+)%s?(.*)"
end

--- `reader` object: read and reread lines from file, list or string
-- Usage:
--    rdr = reader(source,position) -- construct the reader
--    for line, pos, count in rdr do   -- read line if any
--      ...
--      rdr:reread(line)   -- put back (possibly modifed) line for rereading
--      ...
--    end
-- Fields `pos`, `line` and `count`must not be modified externally. 
reader = function(source,linepos)
-- Undocumented feature, provided for debugging: if `linepos` is a function,
-- it overrides the line and position routine constructed by default 
  if type(linepos) ~= 'function' then
    assert(not linepos or type(linepos) =='number',
     "bad argument #2 to reader, expected number, got "..type(linepos))
    if io.type(source)=='file' then
      local lines, seek = source:lines(), source:seek("set",linepos or 0)
      linepos = function()
        local pos = source:seek()
        local line = lines()
        return line and line:gsub("\r$",""), pos  -- strip off CR if any
      end
    elseif type(source)=='string' then
      local init = linepos or 1
      local match = source:sub(init):gmatch"()([^\n]+)" 
      linepos = function()
        local pos,line = match()
        return line,pos+init-1
      end
    elseif type(source)=='table' then 
      local pos = (linepos or 1)-1
      linepos = function()
        pos = pos+1
        return source[pos],pos
      end
    else 
      assert(false,"no default `linepos` defined for type "..type(source))
    end
  end
----
  return setmetatable ( 
  { line = nil,
    pos = nil,
    count = 0,
    reread = function(rdr,line)
      rdr.line = line
--      rdr.count = rdr.count - 1
    end },
  { __call = function(rdr)
      local line = rdr.line
      if not line then
        line, rdr.pos = linepos()
        rdr.count = rdr.count + 1         
      end      
      rdr.line = nil
      return line, rdr.pos, rdr.count
    end } )
end

--- write a line to a GEDCOM file
-- togedcom(file,line,options)
-- options must contain `linelength`. If `line` is too long or contains
-- newlines, it is broken up and issued with the necessary CONC and CONT
-- lines.
to_gedcom = function(file,line,options)
  if not line then return end
  local linelength = options.linelength
  local base = tonumber(line:match"%d")
  local CONC = ("%d CONC "):format(base+1)
  local CONT = ("%d CONT "):format(base+1)
  local conc = ''
  while #line>0 do
    local head, tail = line:match"([^\n]*)\n?(.*)"
    while #head>linelength-#conc do
      local n=linelength-#conc
      if head:sub(n+1,n+1)==" " then n=n-1 end     
      while n>0 and (not utf8.len(head:sub(1,n)) or head:sub(n,n)==" ") do 
        n=n-1 
      end
      assert(n>0)
      file:write(conc,head:sub(1,n),"\n")
      head = head:sub(n+1)
      conc = CONC
    end
    file:write(conc,head:sub(1,n),"\n")
    conc = CONT
    line = tail
  end            
end

local methods = function(object)
  local meth = {}
  for k in pairs(getmetatable(object)) do if not k:match"^_" then
    meth[#meth+1] = k
  end end
  tsort(meth)
  return tconcat(meth," ")
end

local metamethods = function(object)
  local meth = {}
  for k in pairs(getmetatable(object)) do if k:match"^__" then
    meth[#meth+1] = k
  end end
  tsort(meth)
  return tconcat(meth," ")
end

-- Export the utilities and metatables. 
util = {reader=reader, Record=Record, level=level, tagdata=tagdata, 
  keytagdata=keytagdata, assemble=assemble, Message=Message }

meta = { GEDCOM=GEDCOM, RECORD=RECORD, FIELD=FIELD, ITEM=ITEM, 
   MESSAGE=MESSAGE }

glob = { lineno=lineno, tags = tags, methods = methods, 
  metamethods = metamethods, date = _parse_date } 

return { read=gedcom, util=util, help=help, meta=meta, glob=glob }
