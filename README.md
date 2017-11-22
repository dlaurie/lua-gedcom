# lua-gedcom
Read and surf GEDCOM files in Lua.

## Quick start

1. Copy `gedcom.lua`, `lifelines.lua` and `template.lua` into a directory named `gedcom` in your Lua module path.  
2. From the directory in which you keep GEDFILE.ged, start up Lua 5.3 (maybe Lua 5.2 is also OK, but all development work has been in 5.3).

You can then try this:

    gedcom = require "gedcom.gedcom"
    require "gedcom.template"
    ged, readerr = gedcom.read "GEDFILE.ged"
    msg = ged:validate()

You will first get two lines reporting what it read (if not, type `readerr` to see what went wrong), and then a list of messages about things considered to be errors in GEDFILE.ged. These messages are also kept in `msg`.

For example, if your file was exported by WikiTree you will probably get something like this:

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

As you can see, this is not too serious: the standard information about a name is supposed to be in `INDI.NAME`, which is where this package looks for it.

Some other GEDCOMs might have this:

    key I139 is used but nowhere defined
    key I155 is used but nowhere defined
    key I222 is used but nowhere defined
    key I223 is used but nowhere defined

This might be more worrying; some other programs will break. This one should not; tell me if it does. Anyway, to get rid of them, type:

    ged:prune()
    ged:write"GEDFILE-fixed.ged"

As you can see, `ged` is a Lua object representing the whole file. Lines at level 0, 1 and 2 introduce other objects called records, fields and items.

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

The main thrust of the package is reading GECDOM files but primitive editing is possible. For example:

    ged.I10.BIRT.DATE:to"23 Dec 1822"

If instead of using `to`, you write 

    `ged.I10.BIRT.DATE.data="23 Dec 1822"` 

the change will be local to your session: if you do a `ged:write`, the original line will be unchanged.

If you are tolerably familiar with the LifeLines report language, you will be glad to hear that you can retrieve information by expressions like:

    ged.I10:name()       -- the name of I10
    ged.I10:name(true)   -- the name of I10 with surname capitalized
    ged.I10:father()     -- the father of I10

Only a selection of the more common LifeLines functions is provided in this way. They include (but this README may be out of date):

    GEDCOM.indi(gedcom,key)
    GEDCOM.fam(gedcom,key)
    FAM.husband(fam)
    FAM.wife(fam)
    FAM.children(fam)
    INDI.name(indi,capitalize)
    INDI.sex(indi)
    INDI.male(indi)
    INDI.female(indi)
    INDI.parents(indi)
    INDI.father(indi)
    INDI.mother(indi)
    INDI.families(indi)

`GEDCOM`, `FAM` and `INDI` are the names of method tables not visible without effort. You do not need them explicitly, since object-oriented calls like `ged:fam(key)` or `fam:children()` do the job neatly.

In the spirit of LifeLines, but not actually in it, is `INDI.refname`, which gives you a full name with lifespan in brackets. This usually is unique (at least for deceased individuals) in your database. 

Less-used LifeLines functions can be added by:

    require "gedcom.lifelines"  -- the result should be 'true'

This Quickstart is not intended to be comprehensive — full documentation is provided in the extensive comments in `gedcom.lua` and may one day be available as a standalone manual — but to whet your appetite, here is one rather convenient little function, available at all levels from GEDCOM to ITEM.

    for record in ged:tagged"INDI" do
      for field in record:tagged('WWW') do
        print(record.key,field.data)
      end
    end

Oh, and do not expect much from the currently available examples. The package has changed a great deal since they were written.

## Uitvoer na GISA se formaat

1. Kopieer die `GISA` omslag van hierdie pakket met al sy inhoud na jou eie gebruikerspasie. 
2. Maak 'n `gedcom` omslag binne hom en skuif die `.lua`-lêers in die hoofgedeelte van hierdie pakket, soontoe.
3. Kopieer jou eie GEDCOM-lêer ook na die `GISA` omslag.

Die inhoud behoort iets van hierdie aard te lyk:

    gedcom
    GEDFILE.ged
    gisa.css
    gisa.lua
    gisa-template.html
    maak-gisa-uit-gedcom.lua
    Makefile

Tik nou 

   lua maak-gisa-uit-gedcom.lua GEDFILE

en druk net elke keer `Enter`. Jy sal iets sien soos:

    Gebruik so: 
    
       lua maak-gisa-uit-gedcom.lua 
    
    Vrae sal gevra word. By party vrae is daar 'n wenk. Soms is dit 
    'n hele woord; dan is die hele woord 'n voorgestelde antwoord.
    Soms is net 'n paar letters waarvan een 'n hoofletter is: daardie 
    hoofletter is die voorgestelde antwoord. As die voorstel aanvaarbaar 
    is, hoef slegs Enter gedruk te word, anders moet 'n ander woord, of
    een van die ander letters, soos die geval mag wees, ingetik word,
    gevolg deur Enter.
    
    Naam van GEDCOM-lêer? [GEDFILE]
    Reading GEDFILE.ged
    3140 lines, 20 records
    'n Rapport oor jou GEDCOM staan in GEDFILE.log
    Wil jy die rapport ook nou sien? [jN]
    Het jy 'n lêer met voorkeure? [jN]
    Die stamvader is dalk	I1	Adam VAN EEDEN 
    Net afstammelinge in die manlike lyn? [Jn]
    GEDFILE.html is uitgeskryf 
    
Die lêer `GEDFILE.html` is geskik om net so in jou woordverwerker ingetrek te word. Jy kan dit dan as `GEDFILE.docx` bêre of na `GEDFILE.pdf` uitvoer.

'n Meer outomatiese opsie, as jy LibreOffice en GNU-Make het, is:

    make GEDFILE.docx
    make GEDFILE.pdf


