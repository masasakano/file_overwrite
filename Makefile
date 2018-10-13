ALL	= 

objs	= 

.SUFFIXES:	.so .o .c .f

#.o.so:
#	${LD} ${LFLAGS} -o $@ $< ${LINK_LIB}

all: ${ALL}


.PHONY: clean test doc
clean:
	$(RM) bin/*~

test:
	rake test

doc:
	yard doc; ruby -r rdoc -e 'puts RDoc::Markup::ToMarkdown.new.convert File.read("README.en.rdoc")' > .github/README.md; ls -lF doc/file.README.en.html .github/README.md

