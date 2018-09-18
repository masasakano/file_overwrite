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
	yard doc

