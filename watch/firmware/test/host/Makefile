# Host-side tests of the Cyclift Watch OS domain code (no hardware). `make` builds and runs everything; non-zero exit on failure.
CXX ?= g++
CXXFLAGS ?= -std=gnu++17 -O1 -Wall -Wextra -Wno-missing-field-initializers -DCYW_HOST
all: run gallery-run
test_domain: test_domain.cpp ../../src/domain/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ test_domain.cpp
gallery: gallery.cpp ../../src/domain/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ gallery.cpp
run: test_domain
	./test_domain
gallery-run: gallery
	./gallery gallery-out
clean:
	rm -rf test_domain gallery gallery-out
.PHONY: all run gallery-run clean
