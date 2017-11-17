# Makefile clutter basics: 
#   Intermediate files that do not already exist are removed after the final 
# target has been successfully made. 
#   Intermediate files that already exist are not removed, but may be remade. 

default: Laurie-477-gisa.html

%-descendants.luax: 
	lua get-from-wikitree.lua $*

%-gisa.txt: %-descendants.luax
	lua maak-gisa.lua $*

%-stamboom.txt: %-descendants.luax
	lua maak-gisa.lua $* almal

%.ged: %.saf gedcom/saftxt.lua
	lua gedcom/saftxt.lua $*.saf 

%.html: %.txt gisa.css gisa.lua 
	pandoc --template=gisa-template.html -H gisa.css $*.txt -o $*.html -t gisa.lua

# About the following conversions: THEY FAIL QUIETLY AND SUCCEED NOISILY.
# I.e. if the conversion worked, there will be a message reporting what 
# file it wrote, if not there is no message.
# The reason for failure is usually that LibreOffice is already running 
# on your computer. Close it and retry.

%.docx: %.html
	libreoffice --convert-to docx:"MS Word 2007 XML" $*.html 2> /dev/null

%.pdf: %.docx
	libreoffice --convert-to pdf:writer_pdf_Export $*.docx 2> /dev/null

TDLawrie.html: TDLawrie.ged
	lua maak-gisa-uit-gedcom.lua TDLawrie Lawrie -Ia -y

JLangenegger.html: JLangenegger.ged
	lua maak-gisa-uit-gedcom.lua JLangenegger Langenegger -Ia -y
