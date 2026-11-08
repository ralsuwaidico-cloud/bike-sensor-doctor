# Host-side tests of the Cyclift Watch OS domain code (no hardware). `make` builds and runs; non-zero exit on failure.
CXX ?= g++
CXXFLAGS ?= -std=gnu++17 -O1 -Wall -Wextra -DCYW_HOST
all: run
test_domain: test_domain.cpp ../../src/domain/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ test_domain.cpp
run: test_domain
	./test_domain
clean:
	rm -f test_domain
.PHONY: all run clean
