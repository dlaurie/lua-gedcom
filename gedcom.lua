--- gedcom.lua  © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Object-oriented representation of GEDCOM files
-- Lua Version: 5.3 (should work with 5.2, but has not extensively been 
--   so tested)
-- The module returns a table with fields: `new, read, help, util, glob, meta`.
-- Look at 'help' for more information.
-- BUGS: 
--   Conversion from ANSI/ANSEL to UTF-8 is not supplied.
--   Sensitive about SEX. I.e. does not warn if there is no SEX, which
--     later causes problems when deciding on s/o, d/o, c/o. No attempt
--     is made to deduce SEX from context.
--   Does not give a proper message when an (illegal) attempt is made to
--     create a new person when the nuclear link is unfinished.

local help = [[
The module returns a table, here called `gedcom`, containing:
  `help` This help string.
  'new`  A function which constructs an empty GEDCOM container and optionally 
   initializes custom fields.
  `open` A function which returns a file-like object with methods `read`
    and `close`, rather like `io.open` except that the `read` method returns
    a Level 0 GEDCOM record.
  `read` A function which uses `open` and `new` to read a GEDCOM file into 
    a new container, here called `ged`, and returns a message, here called 
    `msg`, suitable for writing to a log file. If construction failed, 
    `ged` is nil and `msg` gives the reason for failure.
  `meta` The metatables of GEDCOM-related objects: GEDCOM, RECORD, MESSAGE 
    and tag-specified metatables like INDI, FAM and DATE. 
  `glob` A few non-member functions that might be useful outside this file.
  `util` A table containing utility functions. They are provided mainly 
    for the convenience of code maintainers, and are documented briefly 
    below in LDoc format compatible with the module `ihelp` available 
    from LuaRocks.

`gedcom.read` takes one argument, which must be the name of an existing 
GEDCOM file. The extension '.ged' may be omitted, but other extensions, 
including '.GED', must be supplied. Thus you will normally have the following 
lines in your application:

    gedcom = require "gedcom"
    ged, msg = gedcom.read(GEDFILE) 

`gedcom.open` and `gedcom.new` are lower-level components, usually not called
directly by the user.

GEDCOM lines are parsed according to the rule that each line must have a level 
number, may have a key, must have a tag, and must have data (but the data may 
be empty). Every line except those with tag CONC or CONT is represented in Lua
by an object called a record. See RECORD.help.

CONC and CONT lines do not get there own records. Their contents is 
concatenated (in the case of CONT, with an intervening a newline) to the data 
of the main line to which they belong. If the entire file is thought of as one 
string, the effect is as if the strings "\nCONC " and "\nCONT " have been 
replaced by "" and "\n", respectively. 

The GEDCOM file is stored in an object called a _container_, an annotated 
array of Level 0 records. See GEDCOM.help.

Containers and records have an __index metamethod such that you can say 
`ged.HEAD.CHAR.data`, `ged.I1.NAME`, etc. This indexing is read-only in the 
sense that you can't replace an object that way. Nothing stops you from 
assigning a value to e.g. `ged.I1`, but that value will shadow the the 
original record that you retrieved as `ged.I1`. If you then assign nil to 
`ged.I1`, the original will reappear.]]

-- initialize metatables
local GEDCOM = {__name="GEDCOM container"}
local RECORD = {__name="GEDCOM record"}
local MESSAGE = {__name="GEDCOM message list"}
local INDI = {}
local FAM = {}
local DATE = {}
local NAME = {}
local CHIL = {}
local HUSB = {}
local WIFE = {}

GEDCOM.help =[[
A GEDCOM _container_ is a table (metatable GEDCOM) containing GEDCOM records 
as items 1,2,...,. and the following fields:

  INDI        A table in which each field gives the number of the record 
              defining the individual with that key (at signs stripped off).
  FAM         A table in which each field gives the number of the record
              defining the family with that key (at signs stripped off). 
  OTHER       A table in which each field gives the number of the record
              defining a keyed record not tagged INDI or FAM.
  firstrec    A table in which each field is the number of the first 
              record with that tag (unkeyed records only).
  _INDI       A list of records with tag `INDI` in their original order.
  _FAM        A list of records with tag `FAM` in the original order.
  msg         List of messages associated with processing this GEDCOM.
              In addition, each line may have its own `msg`.

If the container was read from a file, it also has:

  filename    The name of the GEDCOM file.

Indexing of a GEDCOM container is extended in the following ways:
  1. Keys. Any key occuring in a Level 0 line can be used, with or without 
     at-signs, as an index into the container. (This is the purpose 
     of INDI, FAM and OTHER.)
  2. Tags. Any tag in an _unkeyed_ Level 0 record can be used as an index
     into the container, and will retrieve the _first_ unkeyed record 
     bearing that tag, as given in `firstrec`.
  3. Methods. Functions stored in the GEDCOM metatable are accessible in
     object-oriented (colon) notation, and all fields stored there are 
     accessible by indexing into the container, except when shadowed.
]]

RECORD.help = [[
A GEDCOM _record_ is a table (metatable RECORD) in which `line` contains 
a Level 0 line from a GEDCOM file. It may as items 1,2,..., contain 
subrecords. 
Records have the following fields:
   `line`: the original line as read in, but with `CONC` and `CONC` taken
into account as described in gedcom.help.
   `key`: a GEDCOM key such as `I1`, `F10` etc, located inside at-signs 
between the level number and the tag on a line in the GEDCOM file. Usually 
but not necessarily non-nil only at Level 0.
   `tag`: a GEDCOM tag such as INDI, DATE etc. Uppercase and underscores only.
   `data`: whatever remains of `line` after the first space following the tag. 
May be empty but not nil. If non-empty, the first character is not a blank.
   `prev`: the higher-level record or container to which the record belongs.
   `msg`: a message object. May be nil. See MESSAGE.help.

If the record was read from a file, it also has:

   `size`: the number of actual lines in the original GEDCOM file that the 
record occupies.    
   `pos`: offset in lines from the start of `prev`
   `count`: offset in bytes from the start of `prev`

Indexing of records is extended as follows:
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

MESSAGE.help = [[
Customizable messaging. 

Msg = Message(translate) constructs a message processor with a custom 
  translation table, which is stored as `Msg.translate`. If no translation 
  table is given, GEDCOM.translate is used. 

Msg:append ([status,][lineno,]message,...) appends a parameterized message to 
    the processor, constructed as 'message:format(...)'. 
  `status` is an optional boolean argument: if omitted, the message is 
    purely informative; if `true`, it describes an error; if `false`, 
    a warning. It is recommended to put 
        local Error, Warning = true, false
    at the top of your program file to provide readable upvalues.
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

-----------------------------------------------------------------------------

-- Usage of 'assert' in this package is to catch program errors. For example,
-- if a line in a GEDCOM file has no tag, it is a data error and is reported
-- via a Message, but if a line in an already constructed GEDCOM object has
-- no tag, it is a program error since those lines should have been caught
-- at an earlier stage.

-- declare some utilities as upvalues
local append, tconcat, tsort, tremove = 
  table.insert, table.concat, table.sort, table.remove
local meta  -- forward declaration of metatable collection 
local -- forward declaration of utilities
   Record, reader, level, tagdata, keytagdata, to_gedcom, lineno, tags,
   tagend
-- forward declaration of private methods
local _read, parse_date 

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
  if message == nil or not message:match"%S" then return end
  message = msg.translate[message] or message
  local ok, fmsg = pcall(string.format,message,select(tail,...))
  assert(ok,fmsg)
  if lineno then fmsg = ("%6d:  %s"):format(lineno,fmsg) end
  append(msg,fmsg)
  if status~=nil then 
-- the 'rawcount' table can serve as a starting point for the construction 
-- of a translation table
    msg.rawcount[message] = (msg.rawcount[message] or 0) + 1
    msg:_error(fmsg) 
  end
end;

MESSAGE.concat = function (msg,delim)
  return tconcat(msg,delim or "\n")
end 

MESSAGE.__index = MESSAGE

MESSAGE._error = function(msg,message)
  local count = (msg.count[message] or 0) + 1
  msg.count[message] = count
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
  append(buffer,object.line)   
  for k=1,#object do
    append(buffer,assemble(object[k]))
  end
  return tconcat(buffer,"\n")
end

--- nonblank(s) is s if s is a non-blank string, otherwise nil
local function nonblank(s)
  if type(s)=='string' and s:match"%S" then return s end
  return nil
end

    do
local _status = {AFT="AFT",BEF="BEF",ABT="ABT",EST="EST",CAL="CAL",
   FR="FR",TO="TO",C="ABT",FROM="FR",BET="FR",AND="TO",VOOR="BEF"}
local _month = {JAN=1,FEB=2,MAR=3,APR=4,MAY=5,JUN=6,JUL=7,AUG=8,SEP=9,
   OCT=10,NOV=11,DEC=12}
--- input: 
--   data   string    (normally the `data` on a DATE line)
--   lax    number    progressively relax strictness
--      lax = 0   strict GEDCOM with case-insensitve English month names
--      lax = 1   also allow some synonyms for qualifiers and month names
--      lax = 2   also allow digits-only dates with separators
--      lax = 3   also allow YYYYMMDD without separators
--      lax = 4   if all else fails, the first four-year sequence of digits
--                is taken for 'year'
-- output: one of:
--   nil, message
--   year, month, day, status, later  with at least year non-nil
-- The output parameters are of type number, number, number, string, table.
-- If present, later.year, later.month, later.day and later.status have the
-- obvious meanings for a second date besides the main date, and
-- later.timespan combines the years from both dates into a string like
-- "1652-1688".

parse_date = function(data,lax)
  if type(data)=='table' then data = data.data end
  assert(type(data)=='string',
    'Bad argument #1 to parse_date: expected string, got '..type(data))
  local word = data:gmatch"%S+"
  local status, day, month, year
  local item = word()
  if not item then
    return 
  end
  if _status[item:upper()] then
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
  n = item and _month[item:upper()]
  if n then
    month = n
    item = nil
  end
  item = item or word()
  if item and item:match"^%d%d%d%d$" then
    year = tonumber(item)
  end
  if day and not month and not year then
    return day, nil, nil, status
  end
  if not year then
    year = data:match"%d%d%d%d"
    if year then status = _status.ABT end
  end
--- and not word() TODO
  if year and not (day and not month) then    
    return year, month, day, status
  else
    return nil,("Nonstandard date format: %s"):format(data)
  end  
end  
    end

--- constructs an empty GEDCOM container and initializes custom fields
-- by shallow-copying them from the given table. Standard fields like
-- INDI and 'firstrec' are **not** copied.
local gedcom_new = function(tbl)
  tbl = tbl or {}
  local ged = setmetatable ( {
    INDI = {},
    FAM = {},
    OTHER = {},
    _INDI = {},
    _FAM = {},
    firstrec = {}, 
    msg = Message(),  -- a new Message for each container
    },
    GEDCOM)
  for k,v in pairs(tbl) do if not ged[k] then
    ged[k] = v
  end end
  return ged
end

--- Opens a GEDCOM file to be read record by record.
-- Returns a file-like object with 'read' and 'close' methods.
-- 'ged' is an optional GEDCOM container, to be inserted as the 'prev'
-- field in each record.
local gedcom_open = function(filename,ged)
  local gedfile, errmsg
  if type(filename)~='string' then 
    return nil,"gedcom.read: expected filename, got "..type(filename)
  end
  if filename:match"%S" then 
    gedfile, errmsg = io.open(filename) 
    if not gedfile and not filename:match"%..+" then 
      filename = filename..".ged"
      gedfile, errmsg = io.open(filename) 
    end
  end
  if not gedfile then return nil, errmsg end
  local rdr = reader(gedfile);
  return {
    read = function() return Record(rdr,0,ged) end;
    close = function() gedfile:close() end;
  }
end  

--- constructs a GEDCOM container and reads a GEDCOM file into it.
-- This is deliberately a constructor and not a GEDCOM method: you can't 
-- read a GEDCOM file into an old GEDCOM container.
local gedcom_read = function(filename)
  local ged = gedcom_new{filename=filename}
  local msg = ged.msg 
  local gedfile, errmsg = gedcom_open(filename,ged)
  if not gedfile then return nil, errmsg end
-- we now have a freshly-opened gedfile
  msg:append("Reading %s",filename)
  for rec in gedfile.read do
    ged:append(rec)
  end
  msg:append("%s bytes, %s lines, %s records, %s individuals, %s families",
    ged[#ged].pos + #ged[#ged].line,
    ged[#ged].count + ged[#ged].size - 1,
    #ged,
    #ged._INDI,
    #ged._FAM)
  gedfile:close()
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
  assert(type(idx)=='number',
    "Invalid key type for GEDCOM container: "..type(idx))
end

-- methods of a GEDCOM container

local function dolines(ged,func)
  func(ged.line)
  for _,record in ipairs(ged) do
    dolines(record,func)
  end
end
GEDCOM.dolines = dolines
RECORD.dolines = dolines

local function traverse(ged,func)
  func(ged)
  for _,record in ipairs(ged) do
    traverse(record,func)
  end
end
GEDCOM.traverse = traverse
RECORD.traverse = traverse

--- Append a record to a GEDCOM container
GEDCOM.append = function(ged,rec)
  if not rec then return end
  assert(level(rec.line)==0,
    "Can't append this level to a container: "..rec.line)
  rec.prev = rec.prev or ged
  local firstrec = ged.firstrec
  local k = #ged + 1
  local key, tag = rec.key, rec.tag
  if key and tag then
    (ged[tag] or ged.OTHER)[key] = k
    if ged[tag] then  
      append(ged["_"..tag],rec)
    end
  end
  if tag and not key then
    firstrec[tag] = firstrec[tag] or k
  end
  ged[k] = rec
end  

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
-- If options.prune is specified, only lines allowed by 'template'
-- are written.
GEDCOM.to_gedcom = function(object,file,options,template)
  template = template or object.template or {}
  to_gedcom(file,object.line,options)
  for _,record in ipairs(object) do
    local subtemplate = template[record.tag]
    if subtemplate or not options.prune then
      record:to_gedcom(file,options,subtemplate)
    end
  end
end

--- ged:find(...)
-- Select records from a GEDCOM collection that satisfy all the given
-- conditions, each of which may be:
--   a function of a record that returns the record if it is to be included
--     and nil or nothing otherwise
--   a table that certain fields in the record must match. See RECORD.test.
-- The return value is a new GEDCOM collection containing only the selected
-- fields.
GEDCOM.find = function(ged,...)
  local sheaf = gedcom.new()
  local n = select('#',...)
  for _,v in ipairs(ged) do
    local ok = true
    for k=1,n do
      local condition = select(k,...)
      if type(condition) == 'function' then ok = condition(v)
      elseif type(condition) == 'table' then ok = v:test(condition)
      end
      if not ok then break end
    end
    if ok then sheaf:append(v) end
  end 
  return sheaf
end 

--- for record,n in gedcom:tagged(pattern) do
-- loop over all records that whose tag matches the specified pattern
GEDCOM.tagged  = function(gedcom,pattern)
  local k,n = 0,0
  return function()
    repeat
      k=k+1
      local v = gedcom[k]
      if not v or v.tag:match(pattern) then 
        n=n+1
        return v,v and n
      end
    until false
  end
end
RECORD.tagged = GEDCOM.tagged

--- for field[,cap1[,cap2,...]] in record:withdata(pattern) do
-- loop over all fields that whose 'data' matches the specified pattern
-- You can specify as many captures as you expect from the pattern.
RECORD.withdata = function(record,pattern)
  local k = 0
  return function()
    repeat
      k=k+1
      local v = record[k]
      local match = v and v.data:match(pattern)
      if match then return v,v.data:match(pattern) end
    until not v
  end
end

--- build an index of records keyed by the data of a specified tag,
--  or by the value of a given function applied to the record.
--      index,duplicates = ged:build(tag[,rectag])
--  If 'rectag' is specified (e.g. 'INDI' or 'FAM'), only records
--     with that tag will be candidates for inclusion.
--- If 'tag' is a function, you will get
--      index[tag(record)] = record
--  If 'tag' is a string, you will get
--      index[record[tag].data] = record
--  If a key occurs more than once, only the first occurrence is in 'index'.
--    All its occurrences, including the first, are returned in 
--    'duplicates', which differs from 'index' in that the values are not 
--    records but lists of records.   
--  Examples:
--    ged:build "NAME" keys records by the NAME field 
--    ged:build(INDI.refname) keys records by reference name
GEDCOM.build = function(ged,tag,rectag)
  local index, duplicates = {}, {}
  local function bank(key,value)
    if not (key and value) then return end
    if index[key] then
      local dup = duplicates[key]
      if dup then dup[#dup+1] = value
      else duplicates[key] = {index[key],value}
      end
    else index[key] = value
    end
  end 
  if type(tag) == 'function' then
    for _,record in ipairs(ged) do 
      if not rectag or record.tag == rectag then       
        bank(tag(record),record) 
      end
    end
  elseif type(tag) == 'string' then 
    for _,record in ipairs(ged) do 
      if not rectag or record.tag == rectag then   
        local key = record[tag]
        bank(key and key.data,record,num) 
      end
    end
  else assert(false,"argument 'tag' to 'build' must be function or string")
  end
  return index,duplicates
end 

--- object, message = Record(rdr,base,prev)
--  Reads one GEDCOM object at level `base`, getting its input from the
--  reader `rdr` (see `reader`). One return value may be nil, but not both.
Record = function(rdr,base,prev)
  local msg=Message()
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
  local record = setmetatable( {line=line,pos=pos,key=key,tag=tag,
     data=data,msg=msg,prev=prev,size=1,count=count}, RECORD) 
  if record._init then record:_init() end
  for line, pos, subcount in rdr do
    local lev = tonumber(line:match"%s*%S+") 
    if not lev then 
      print(line)
      msg:append(Error,"line does not start with valid level number")
    end
    if lev<=base then
      rdr:reread(line)
      break
    end
    append(lines,line)
    record.size = record.size+1
  end
  if #lines>0 then 
    local subrdr = reader(lines)
    repeat
      local subrec = Record(subrdr,base+1,record)
      record[#record+1] = subrec
    until not subrec
  end
  if #msg==0 then record.msg = nil end   -- delete empty messages
  return record
end

--- RECORD methods

RECORD.__index = function(record,idx)
-- if it isn't there, it isn't there
  if type(idx)=='number' then return nil end
-- is it a metamethod?
  local metamethod = getmetatable(record)[idx]
  if metamethod then return metamethod end
-- is there a specialized method for this type of record?
  local methods = meta[rawget(record,"tag")]
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

--- record:test(program)
-- Returns 'record' if it passes all the tests in 'program', otherwise
-- return nothing.
-- The tests may be in the list part or the non-list part of 'program'.
-- Tests in the list part must be functions. They are applied to 'record'
-- in the specified order and must return a true value to pass.
-- The other tests are each specified by a pair (tag,pat).
-- * If record[tag] is nil, the test fails.
-- * If record[tag] is a function, 'result = record[tag](record)' is evaluated.
--   If 'pat' is boolean, the test succeeds if it has the same truth value 
--     as 'result'.
--   If 'result' and 'pat' are both strings, the test succeeds if 'result'
--   matches 'pat'.
-- * If record[tag] and 'pat' are both strings, the test succeeds if
-- record[tag] matches 'pat'.
-- * If record[tag] is a table and 'pat' a string, the test succeeds if 
-- record[tag].data matches 'pat'. 
-- * If record[tag] and 'pat' are both tables, the test succeeds if the
-- recursive call record[tag]:test(tag) does.
-- If none of the above apply, the test fails.
-- If 'tag' is 'lifespan', '-' in 'pat' stands for itself, it is not magic.
RECORD.test = function(record,program)
  for tag,pat in pairs(program) do 
    local rec = record[tag]
    if not rec then return end
    if tag=='lifespan' then pat=pat:gsub("%%?%-","%%-",1) end
    if type(rec)=='function' then 
      local result = rec(record)
      if type(pat) == 'boolean' then
        if not ((result and pat) or (not result and not pat)) then return end
      elseif type(pat) == 'string' and type(result) == 'string' then
        if not result:match(pat) then return end
      else return
      end
    elseif type(rec)=='string' and type(pat)=='string' then
      if not rec:match(pat) then return end
    elseif type(rec)=='table' then
      if type(pat)=='string' then
        if not rec.data:match(pat) then return end
      elseif type(pat)=='table' then 
        if not (rec.test and rec:test(pat)) then return end      
      else return 
      end
    else return
    end
  end 
  return record
end

-- If options.prune is specified, only lines allowed by 'template'
-- are written.
RECORD.to_gedcom = function(item,file,options,template)
  template = template or {}
  to_gedcom(file,item.line,options)
  for _,subitem in ipairs(item) do
    local subtemplate = template[item.tag]
    if subtemplate or not options.prune then   
      to_gedcom(file,subitem.line,options)
    end   
  end
end

RECORD._tags = function(RECORD)
  if record.prev._tags then
    return record.prev:_tags() .. "." .. record.tag
  else return record.tag
  end
end
tags = RECORD._tags

RECORD._lineno = function(record)
  if record.prev._lineno then
    return record.prev:_lineno() + record.count 
  else return record.count
  end
end
lineno = RECORD._lineno

--- Change 'data', also updating `line`.
RECORD.to = function(record,data)
  local pos = tagend(record.line)
  assert(pos,'line has no tag')
  local methods = meta[record.tag] 
  local check = methods and methods.check
  if check then check(data) end
  record.data = data
  record.line = record.line:sub(1,pos-1) .. ' ' .. data
  local init = record._init
  if init then init(record) end
end

GEDCOM.message = function(ged,...)
   ged.msg:append(tconcat({...},' '))
end 

RECORD.message = function(record,...)
  if record.prev then
    record.prev:message((record.key or record.tag),...)
  else
    print(tconcat({(record.key or record.tag),...},' '))
  end
end

--- Undocumented feature: `-ged.HEAD` etc puts together a record or message.
-- Not a whole GEDCOM.
RECORD.__unm = assemble
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

--- tagend(line) is the position after the tag
tagend = function(line)
  assert(type(line)=="string")
  return line:match"%s*%d+%s+@%S+@%s+%S+()" or
            line:match"%s*%d+%s+%S+()"
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
  local linelength = options.linelength or 128
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

-------------------- specialized tag functions -------------------------

------ DATE functions

--- A DATE record has up to five fields.
-- _status, _year, _month, _day, _later
-- _status: one of ABT,CAL,EST,AFT,BEF
-- _year, _month, _day: integers
-- _later: another table with similar fields status, year, month, day
--    Used for a later date when the true date falls in a certain timespan,
--    and also to delimit a period. In the latter case, the field 'timespan'
--    is set to a string like "1861-1892".
-- For more detail, see the cooments to the function `parse_date` which is 
-- exported as `gedcom.glob.date`.

DATE.check = function(data)
  if not parse_date(data) then
    error("Improperly formed date "..tostring(data))
  end
end

-- Adds fields to a DATE record
DATE._init = function(date)
  if not date.data:match"%S" then return end
  date._year, date._month, date._day, date._status, date_later = 
    parse_date(date.data) 
  if not date._year then 
    if not date._done then date:message(date._month) end
    date._month, date._day, date._status = nil 
  end
  date._done=true
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

--- Result of comparison can be:
--  -2    first date is earlier if ABT qualifiers are neglected
--  -1    first date is equal or earlier
--   0    the dates are equal
--   1    first date is equal or later
--   2    first date is later if ABT qualifiers are neglected
--  nil   an argument is invalid
-- false  the dates cannot be compared
-- true   the dates may be equal but are not given to the same precision
DATE.compare = function(date1,date2)
  if not (type(date1)=='table' and type(date1.year)=='function' and
          type(date2)=='table' and type(date2.year)=='function') then 
    return nil 
  end
  local   year1,        month1,        day1,        status1 =  
    date1:year(), date1:month(), date1:day(), date1:status()
  local   year2,        month2,        day2,        status2 =  
    date2:year(), date2:month(), date2:day(), date2:status()
  if not (year1 and year2) then return nil end
  local compare
-- calculate comparison ignoring qualifiers
  if year1<year2 then compare=-1
  elseif year1>year2 then compare=1
    elseif month1 and month2 then
      if month1<month2 then compare=-1
      elseif month1>month2 then compare=1
        elseif day1 and day2 then
          if day1<day2 then compare=-1
          elseif day1>day2 then compare=1
          else compare=0
          end
        elseif day1 or day2 then compare=true
      else compare=0
      end
    elseif month1 or month2 then compare=true
  else compare=0
  end
-- return this when unqualified
  if not (status1 or status2) then return compare end
-- handle 'false' returns
  if status1=='BEF' and (status2=='BEF' or compare==1) or
     status1=='AFT' and (status2=='AFT' or compare==-1) or
     status2=='BEF' and compare==-1 or
     status2=='AFT' and compare==1
    then return false
  end  
-- in other cases when 'BEF' or 'AFT' is specified, result must be -1 or -1 
  if status1=='BEF' or status2=='AFT' then compare=-1
  elseif status1=='AFT' or status2=='BEF' then compare=1
  end 
-- if any 'ABT' is around, make things imprecise
  if status1=='ABT' or status2=='ABT' then
    if compare==0 then return true 
    elseif compare==1 or compare==-1 then return 2*compare
    end
  end
  return compare
end

------ NAME functions

local name_pattern = '^([^/]-)%s*/([^/]+)/%s*([^/]*)$'

NAME.check = function(data)
  if not data or not data:match(name_pattern) then
    error("Improperly formed name "..tostring(data))
  end
end

NAME.name = function(name,options)
  local nick
  if options.nickname then
    nick = nonblank(name.NICK and name.NICK.data)
    if nick then 
      nick = options.nickname:format(nick)
    end
  end
  local pre, surname, post = name.data:match(name_pattern)
  if not pre then 
    if nick then return name.data .. " "..nick
    else return name.data
    end
  end
  if options.capitalize then surname = surname:upper() end
  if options.omit_surname then surname = nil end
  local buf = {}
  append(buf,nonblank(pre))
  append(buf,nick)
  append(buf,surname); 
  append(buf,nonblank(post))
  return tconcat(buf,' ')
end  

--- LifeLines-compatible name(), with extension to allow table-valued
-- 'options' instead of a boolean.
INDI.name = function(indi,capitalize,extra)
  assert(not extra,"INDI.name no longer supports a third argument")
  local options
  if type(capitalize)=='table' then 
    options = capitalize
  else
    options = {capitalize=capitalize}
  end
  local NAME = indi.NAME
  return NAME and NAME:name(options)
end

------------------ Constructors and maintainers ---------------------

local key_pattern = "@(.+)@"

--- construct a new record from its components key (may be nil), tag,
-- data (defaults to '')
RECORD.new = function(key,tag,data)
  local record = {key=key, tag=tag, data=data}
  record.line = RECORD.join(record)
  return setmetatable (record, RECORD)
end

--- join the components of a record: key (may be nil), tag (must not be nil) 
-- and data (defaults to ''). Level is nominally 0 but will be set to its
-- correct value whan the record is appended to its parent.
RECORD.join = function(record)
  local tag=record.tag
  assert(type(tag)=='string' and tag==tag:upper(),
    "bad tag in RECORD.join, expected uppercase string, got "..tostring(tag))
  local data = record.data or ''
  local level = 0
  local key = record.key
  local line = {level}
  if key then 
    line[#line+1] = '@'..key..'@'
  end
  line[#line+1] = tag
  line[#line+1] = data
  return tconcat(line," ") 
end

--- Append a field to this record. The parent and level number of the field
-- are set to the correct linked values.
RECORD.append = function(record,field)
  field.prev = record
  field.line = level(record.line)+1 .. ' ' .. field.line:match"%S+%s+(.*)"
  record[#record+1] = field
end

------------ additional GEDCOM and RECORD -------------

-- Many of these functions logically belong in lifelines.lua, but are
-- needed already.

-- A stub is an individual without any family.
INDI.is_stub = function(indi)
  return not (indi.FAMS or indi.FAMC)
end

GEDCOM.indi = function(gedcom,key)
  local indi = gedcom[key]
  if indi and indi.tag == "INDI" then return indi end
end

GEDCOM.fam = function(gedcom,key)
  local fam = gedcom[key]
  if fam and fam.tag == "FAM" then return fam end
end

FAM.husband = function(fam)
  local husband = fam.HUSB
  if husband then return fam.prev:indi(husband.data) end
end

FAM.wife = function(fam)
  local wife = fam.WIFE
  if wife then return fam.prev:indi(wife.data) end
end

FAM.surname = function(fam)
  local surname = fam.SURN and fam.SURN.data
  if surname then return surname end
  local husband = fam:husband()
  surname = husband and husband:surname()
  if surname then return surname end
  local wife = fam:wife()
  return wife and wife:surname()
end

--- for child,k in fam:children() do
FAM.children = function(fam)
  local iter = fam:tagged"CHIL"
  return function()
    local child, n = iter()
    if not child then return end
    return fam.prev:indi(child.data),n
  end
end

FAM.member = function(fam,key)
  for _,v in ipairs(fam) do 
    if v.data and v.data:match(key_pattern) == key then
      return v
    end
  end
end

INDI.sex = function(indi)
  return indi.SEX and indi.SEX.data
end

INDI.male = function(indi)
  return indi:sex() == 'M'
end

INDI.female = function(indi)
  return indi:sex() == 'F'
end

INDI.parents = function(indi)
  local parents = indi.FAMC
  if parents then
    return indi.prev:fam(parents.data)
  end
end

INDI.checkname = function(indi,known)
  if not indi then return end
  local name = indi:refname()
  if known and (name:match"Unknown" or name:match"Anonymous") then return end
  return indi
end

INDI.father = function(indi,known)
  local parents = indi:parents() 
  if parents then 
    return INDI.checkname(parents:husband(),known)
  end
end

INDI.mother = function(indi,known)
  local parents = indi:parents() 
  if parents then
    return INDI.checkname(parents:wife(),known)
  end
end

-- indi:spousein(fam) 
-- if indi is a parent in the family, then the other parent, if any, 
-- is returned, otherwise nothing.
INDI.spousein = function(indi,fam)
  if not fam then return end
  local husband, wife = fam:husband(), fam:wife()
  if indi == husband then return wife
  elseif indi == wife then return husband
  end
end

INDI.by_birthday = function(indi,other)
  local comp = DATE.compare(indi:birthdate(),other:birthdate())
  if type(comp)=='number' and comp<0 then return true end
end

-- for child,k in indi:children() do
-- VARIANT: children, msg = indi:children'table'
--   Returns a table (not an iterator) and a message object 
INDI.children = function(indi,typ)
  local msg = Message()
  local children = {}
  local year=0
  local k=0
  for fam in indi:families() do
    for child in fam:children() do
      children[#children+1] = child
      if not child:birthyear() then
      child:message(("No birthyear for %s %s"):format(child.key,child:name()))
      end
    end
  end
  tsort(children,indi.by_birthday)
  if typ=='table' then return setmetatable(children,{__index=GEDCOM}),msg
  else return function()
    k=k+1
    return children[k],k
    end
  end
end   

--- for family,spouse,k in indi:families() do
INDI.families = function(indi)
  local iter = indi:tagged'FAMS'
  return function()
    local fam, n = iter()
    if not fam then return end
    fam = indi.prev[fam.data]
    return fam, indi:spousein(fam), n
  end
end

INDI.birthyear = function(indi)
  local date = indi:birthdate()
  if not date then return nil end
-- first try '_year', otherwise call 'year' method if any
  local year = date._year or date.year and date:year()
  return year
end

INDI.birthdate = function(indi)
  return indi.BIRT and indi.BIRT.DATE
end

INDI.deathyear = function(indi)
  local date = indi:deathdate()
  return date and date:year()
end

INDI.deathdate = function(indi)
  return indi.DEAT and indi.DEAT.DATE
end

INDI.surname = function(indi)
  if not indi.NAME then print(-indi) end
  return indi.NAME.data:match "/(.*)/"
end

--- A name with vital years in order to aid identification
INDI.refname = function(indi)
  local buf = {}
  append(buf,indi:name(true))
  append(buf,indi:lifespan() or '')
  return tconcat(buf," ")
end

INDI.lifespan = function(indi)
  local lst = {}
  lst[#lst+1] = indi:birthyear()
  lst[#lst+1] = "-"
  lst[#lst+1] = indi:deathyear()
  if #lst>1 then return '(' .. tconcat(lst) ..")" end
end 

FAM.refname = function(fam)
  local buf = {}
  local husband = fam:husband()
  local wife = fam:wife()
  append(buf,husband and husband:name(true))
  append(buf,'x')
  append(buf,wife and wife:name(true))
  return tconcat(buf," ")
end

INDI.age = function(indi)
end  

---------- GEDCOM Toolkit functions ----------

--- Find furthest forefather, omitting stubs.
INDI.forefather = function(indi)
  local progenitor,level = indi,0
  repeat 
    local prog = progenitor:father()
    if not prog or not prog.FAMS then return progenitor,level end
    progenitor, level = prog,level+1
  until false
end

--- find male person with most generations of descendants
GEDCOM.alpha = function(gedcom,surname)
  local main
  local level = 0
  surname = surname:upper()
  for indi in gedcom:tagged"INDI" do
    local indi_surname = indi.surname and indi:surname()
    if indi_surname then 
      if indi_surname:upper() == surname then
        local prog, lev = indi:forefather()
        if lev>level then
          main,level = prog,lev
        end
      end
    else
      print("Individual has no surname",indi.NAME.data)
    end 
  end
  return main
end

--- indi:descendants() 
-- Make a new GEDCOM container whose core is a single individual plus
-- descendants and their spouses, plus parents of the root individual.
-- The individual records are not cloned.
INDI.descendants = function(indi,ged)
  local oldged = ged 
  ged = ged or gedcom_new()
  ged:append(indi)
  if not oldged then
    ged:append(indi:parents());
    ged:append(indi:father())
    ged:append(indi:mother())
  end
  for fam, spouse in indi:families() do
    if spouse then 
      ged:append(spouse)
      ged:append(spouse:parents())
      ged:append(spouse:father())
      ged:append(spouse:mother())
    end
    ged:append(fam)
    for child in fam:children() do
      child:descendants(ged)
    end
  end  
  ged:fix_families()
  return ged
end

--- Ensure that all families referred to in INDI records exist and refer to 
-- that individual.
GEDCOM.fix_families = function(ged)
  for indi in ged:tagged"INDI" do
    for field in indi:tagged"FAM?" do
      local fam = ged[field.data]
      if not fam then
        fam = RECORD.new(field.data:match(key_pattern),'FAM')
        ged:append(fam)
      end
      if not fam:member(indi.key) then
        local role = 'CHIL'
        if field.tag == 'FAMS' then
          if indi:male() then role = 'HUSB'
          else role = 'WIFE'
          end
        end
        fam:append(RECORD.new(nil,role,'@'..indi.key..'@'))
      end
    end
  end      
end

--- Remove non-existent individuals from families
FAM.prune = function(fam)
  local ged = fam.prev
  local k=1
  repeat 
    local key = fam[k].data:match(key_pattern)
    if key and not ged[key] then
      tremove(fam,k)
    else k=k+1
    end
  until not fam[k]
end

GEDCOM.prune = function(ged)
  for fam in ged:tagged"FAM" do
    fam:prune()
  end
end

--- tbl = GEDCOM.match(ged1,ged2,field,rectag)
-- Find matches of equal fields between two GEDCOMs.
-- Returns a table of pairs (k1,k2), where k1 and k2 are both keys of 
-- records with tag 'rectag' in ged1 and ged2 respectively, such that 
--  *  ged1[k1][field] == ged2[k2][field], if field is a string
--  *  field(ged1[k1]) == field(ged2[k2]), if field is a function
GEDCOM.match = function(ged1,ged2,field,rectag)
  local tbl = {} 
  local msg = Message()
  local index1, dup1 = ged1:build(field,rectag)
  local index2, dup2 = ged2:build(field,rectag)
  for k,v1 in pairs(index1) do
    local v2 = index2[k]
    if v2 then
      if dup1[k] or dup2[k] then
        msg:append("Can't yet handle internal duplicates in GEDCOM.match")
      else
        tbl[v1.key] = v2.key
      end
    end
  end
  return tbl
end

--------------------- wind up and return ----------------

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
local util = {reader=reader, Record=Record, level=level, tagdata=tagdata, 
  keytagdata=keytagdata, assemble=assemble, Message=Message, 
  key_pattern = key_pattern, name_pattern = name_pattern }

meta = { GEDCOM=GEDCOM, RECORD=RECORD, 
   INDI=INDI, FAM=FAM, DATE=DATE, NAME=NAME, MESSAGE=MESSAGE }

local glob = { lineno=lineno, tags = tags, methods = methods, 
  metamethods = metamethods, date = parse_date } 

-- TODO move the following stuff elsewhere

--[[ Three starting hyphens to enable global assignment check, two to disable.
setmetatable(_ENV,{__newindex=function(ENV,key,value)
  print('Assigning ',value,' to global variable ',key)
  print(debug.traceback())
  rawset(ENV,key,value) end})
--]]

--[[assert (utf8 and string and table 
    and string.unpack and utf8.len and table.move, 
    "The module `gedcom` needs Lua 5.3")
-- Note on `assert`: it is used to detect programming errors only.
-- Errors in the data are reported in a different way.
--]]

return { open=gedcom_open, read=gedcom_read, new=gedcom_new, 
  util=util, help=help, meta=meta, glob=glob }
