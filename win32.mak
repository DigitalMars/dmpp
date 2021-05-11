
##### Directories

# Where scp command copies to
SCPDIR=..\backup

##### Tools

# D compiler
DMD=dmd
# Make program
MAKE=make
# Librarian
LIB=lib
# Delete file(s)
DEL=del
# Make directory
MD=mkdir
# Remove directory
RD=rmdir
# File copy
CP=cp
# De-tabify
DETAB=detab
# Convert line endings to Unix
TOLF=tolf
# Zip
ZIP=zip32
# Copy to another directory
SCP=$(CP)

MFLAGS=

SRCS=main.d cmdline.d context.d id.d skip.d macros.d textbuf.d ranges.d outdeps.d \
	lexer.d constexpr.d number.d stringlit.d sources.d loc.d expanded.d \
	directive.d file.d charclass.d

DOCS=dmpp.dd LICENSE.md

MAKEFILES=win32.mak posix.mak

targets : dmpp.exe dmpp.html

dmpp.exe : $(SRCS)
	$(DMD) -g $(SRCS) -ofdmpp.exe

release :
	$(DMD) $(MFLAGS) -O -release -inline -noboundscheck $(SRCS) -ofdmpp.exe

profile :
	$(DMD) -profile $(SRCS) -ofdmpp.exe

profilegc :
	$(DMD) -profile=gc $(SRCS) -ofdmpp.exe

unittest : $(SRCS)
	$(DMD) -g $(SRCS) -ofdmpp.exe -unittest -cov

dmpp.html : dmpp.dd
	$(DMD) dmpp.dd -D

clean:
	$(DEL) dmpp.exe

detab:
	$(DETAB) $(SRCS)

tolf:
	$(TOLF) $(SRCS) $(MAKEFILES) $(DOCS)

zip: detab tolf $(MAKEFILES)
	$(DEL) dmppsrc.zip
	$(ZIP) dmppsrc $(MAKEFILES) $(DOCS) $(SRCS)


scp: detab tolf $(MAKEFILES)
	$(SCP) $(MAKEFILES) $(SRCS) $(DOCS) $(SCPDIR)/

