CFLAGS=-std=c99 -Wall -Wextra -Werror -O1 -I../../components/bc_core/include
all: test_bc_xds
	./test_bc_xds
test_bc_xds: test_bc_xds.c ../../components/bc_core/bc_xds.c
	$(CC) $(CFLAGS) -o $@ $^
clean:
	rm -f test_bc_xds
