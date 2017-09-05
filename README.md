# lua-gedcom
Read and surf GEDCOM files in Lua.

## Quick start

1. Copy `gedcom.lua` and `lifelines.lua` into a directory named `gedcom` in your Lua module path.  
2. From the directory in which you keep GEDFILE.ged, start up Lua 5.3.

You can then try this:

    gedcom = require "gedcom.gedcom"
    ged, readerr = gedcom.read "GEDFILE.ged"
    msg = ged:validate()

You will first get two lines reporting what it read (if not, type `readerr` to see what went wrong), and then a list of messages about things considered to be errors in GEDFILE.ged. These messages are also kept in `msg`.

For example, if your file was exported by WIkiTree you will probably get something like this:

       9:  Tag HEAD.COPR ignored and its subrecords skipped
      19:  Tag INDI.NAME.GIVN ignored and its subrecords skipped
      20:  Tag INDI.NAME.SURN ignored and its subrecords skipped
      24:  Tag INDI.WWW ignored and its subrecords skipped
      79:  Tag INDI.OBJE ignored and its subrecords skipped
     104:  Tag INDI.NAME._MIDN ignored and its subrecords skipped
     106:  Tag INDI.NAME._MARN ignored and its subrecords skipped
     403:  Tag INDI.NAME._PGVN ignored and its subrecords skipped
     410:  Tag INDI.EMAIL ignored and its subrecords skipped
     758:  Tag INDI.NAME.NPFX ignored and its subrecords skipped
    1902:  Tag INDI.NAME._AKA ignored and its subrecords skipped

You can retrieve information from your file by expressions like:

    ged.I10           -- the record for individual I10
    ged[10]           -- the tenth record in `ged`
    ged[10].key       -- the key of that record (e.g. I8)
    ged[10].tag       -- the tag of that record (e.g. INDI)
    ged[10].data      -- the data of that record (everything after the tag)
    #ged.I10          -- the number of subrecords in I10
    ged.I10[1]        -- the first subrecord in I10
    ged.I10.NAME      -- the first subrecord with tag NAME in I10
    ged.I10.NAME.data -- the data part of the first NAME line

If you are tolerably familiar with the LifeLines report language, you should also type:

    require "gedcom.lifelines"  -- the result should be 'true'

You can then retrieve information by expressions like:

    ged.I10:name()       -- the name of I10
    ged.I10:name(true)   -- the name of I10 with surname capitalized
    ged.I10:father()     -- the father of I10
    
Full documentation is provided in the extensive comments in `gedcom.lua`.


