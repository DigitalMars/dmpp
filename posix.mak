
##### Directories

# Where scp command copies to
SCPDIR=..\backup

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

SRCS=main.d cmdline.d context.d id.d skip.d macros.d textbuf.d ranges.d outdeps.d \
	lexer.d constexpr.d number.d stringlit.d sources.d loc.d expanded.d \
	directive.d

MAKEFILES=win32.mak posix.mak

dmpp.exe : $(SRCS)
	$(DMD) -g $(SRCS) -ofdmpp

unittest : $(SRCS)
	$(DMD) -g $(SRCS) -ofdmpp -unittest -cov

clean:
	$(DEL) dmpp

detab:
	$(DETAB) $(SRCS)

tolf:
	$(TOLF) $(SRCS) $(MAKEFILES)

zip: detab tolf $(MAKEFILES)
	$(DEL) dmppsrc.zip
	$(ZIP) dmppsrc $(MAKEFILES)
	$(ZIP) dmppsrc $(SRCS)


scp: detab tolf $(MAKEFILES)
	$(SCP) $(MAKEFILES) $(SRCS) $(SCPDIR)/

