
##### Directories

# Where scp command copies to
SCPDIR=../backup

# Source files
S=src/dmpp

##### Tools

# D compiler
DMD=dmd
# Make program
MAKE=make
# Librarian
LIB=ar
# Delete file(s)
DEL=rm
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
ZIP=zip
# Copy to another directory
SCP=$(CP)

SRCS=$S/main.d $S/cmdline.d $S/context.d $S/id.d $S/skip.d $S/macros.d $S/textbuf.d \
	$S/ranges.d $S/outdeps.d $S/lexer.d $S/constexpr.d $S/number.d $S/stringlit.d \
	$S/sources.d $S/loc.d $S/expanded.d $S/directive.d $S/file.d $S/charclass.d

DOCS=LICENSE.md README.md

DDOCS=$S\dmpp.dd

MAKEFILES=win32.mak posix.mak

TARGETS=dmpp.exe dmpp.html

targets : $(TARGETS)

dmpp : $(SRCS)
	$(DMD) -g $(SRCS) -ofdmpp

release :
	$(DMD) -O -release -inline -noboundscheck $(SRCS) -ofdmpp

unittest : $(SRCS)
	$(DMD) -g $(SRCS) -ofdmpp -unittest -cov

dmpp.html : $S/dmpp.dd
	$(DMD) $S/dmpp.dd -D

clean:
	$(DEL) dmpp

detab:
	$(DETAB) $(SRCS) $(DOCS) $(DDOCS)

tolf:
	$(TOLF)  $(SRCS) $(DOCS) $(DDOCS) $(MAKEFILES)

zip: detab tolf $(SRCS) $(DOCS) $(DDOCS) $(MAKEFILES)
	$(DEL) dmppsrc.zip
	$(ZIP) dmppsrc $(SRCS) $(DOCS) $(DDOCS) $(MAKEFILES)


scp: detab tolf $(MAKEFILES)
	$(SCP) $(MAKEFILES) $(DOCS) $(SCPDIR)/
	$(SCP) $(SRCS) $(DDOCS) $(SCPDIR)/src/dmd

