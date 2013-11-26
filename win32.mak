
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

SRCS=main.d

MAKEFILES=win32.mak

dmpp.exe : main.d
	$(DMD) main.d -ofdmpp.exe

clean:
	$(DEL) dmpp.exe

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

