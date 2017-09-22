--- customize.lua © Dirk Laurie  2017 MIT License like that of Lua 5.3
-- Customize the behaviour of validate.lua


-- Edit the template, whitelist and synonyms below to conform to your 
-- flavour of GEDCOM.
--
--    Allowed fields after the equal sign:
-- true: no conditions on the data
-- false: must not appear at this level
-- event: a subrecord with DATE and PLAC allowed
-- date: a line in valid GEDCOM date format
-- any_of: any of the words in the blank-separated list
-- name_pattern: a NAME in valid GEDECOM format (surname between two slashes)
-- key_pattern: a key in valid GEDECOM format (i.e. between two at-signs)
-- { ... };  a list of subrecords
--
--   Allowed fields without an equal sign, directly after {
-- has_key: the line must contain a key before the TAG
-- all the above fields except the list of subrecords

template = [[
  HEAD = { true,
    CHAR = any_of'ANSI ANSEL UTF-8',
    DATE = date,
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
  TRLR = true;
]]

-- the whitelist consists of tags that are assumed to be unconditionally
-- valid at all levels above level 0

whitelist = "NOTE RFN REFN SOUR CHAN"

-- synonyms mean that the tag to the left of the equal sign is treated
-- exactly like the tag to the right of the equal sign 

synonyms = [[
CHRA = "CHR";
]]

-- Change the right-hand side of the following lines to customize your 
-- messages. Do not forget double-quotes before and after! To keep it
-- in English, delete all the lines.
translate = [[
"Data does not match %s%s"; "Data pas nie op %s nie"
"Nonstandard date format:"; "Nie-standaard datumformaat"
"Tag %s ignored and its subrecords skipped"; "Merker %s word geïgnoreer en sy subrekords oorgeslaan"
"Tag %s must have a key"; "Merker %s moet 'n sleutel hê"
]]


