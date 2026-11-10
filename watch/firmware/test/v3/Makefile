# Cyclift Watch v3 — Stage 1 tests on a computer (no hardware, no flashing).
#   make            model tests + LVGL rendering tests (screenshots and report.json in out/)
#   make sizes      font / icon data sizes (the same const data the watch build stores in flash)
# LVGL 8.3.11 is fetched into .deps/ on first use (git).
CXX ?= g++
CC ?= gcc
LVGL ?= .deps/lvgl
SRC := ../../src/ui/v3
EXTRA ?=
DEFS := $(EXTRA) -DCYW_HOST -DCYW_V3POC -DLV_CONF_INCLUDE_SIMPLE -DLV_CONF_PATH=$(abspath $(SRC)/lv_conf_v3.h)
INC := -I$(LVGL) -I$(LVGL)/.. -I$(SRC)
CFLAGS := -O2 $(DEFS) $(INC) -w
CXXFLAGS := -std=gnu++17 -O2 -Wall -Wextra -Wno-missing-field-initializers $(DEFS) $(INC)
BUILD ?= .build
LV_SRCS := $(shell test -d $(LVGL)/src && find $(LVGL)/src -name '*.c')
LV_OBJS := $(patsubst $(LVGL)/%.c,$(BUILD)/lvgl/%.o,$(LV_SRCS))
FONT_OBJS := $(patsubst $(SRC)/fonts/%.c,$(BUILD)/fonts/%.o,$(wildcard $(SRC)/fonts/*.c))

all: model render

$(LVGL)/lvgl.h:
	git clone --depth 1 --branch v8.3.11 https://github.com/lvgl/lvgl.git $(LVGL)

model: test_model.cpp test_time.cpp $(SRC)/*.hpp ../../src/hal/rtc_time.hpp
	@mkdir -p $(BUILD)
	$(CXX) -std=gnu++17 -O1 -Wall -Wextra -DCYW_HOST -o $(BUILD)/test_model test_model.cpp
	$(BUILD)/test_model
	$(CXX) -std=gnu++17 -O1 -Wall -Wextra -o $(BUILD)/test_time test_time.cpp
	$(BUILD)/test_time
	python3 ../../tools/v3/gen_tokens.py --check

$(BUILD)/lvgl/%.o: $(LVGL)/%.c $(SRC)/lv_conf_v3.h
	@mkdir -p $(dir $@); $(CC) $(CFLAGS) -c $< -o $@
$(BUILD)/fonts/%.o: $(SRC)/fonts/%.c
	@mkdir -p $(dir $@); $(CC) $(CFLAGS) -c $< -o $@
$(BUILD)/icons.o: $(SRC)/cyv3_icons.c
	@mkdir -p $(dir $@); $(CC) $(CFLAGS) -c $< -o $@
$(BUILD)/ui.o: $(SRC)/cyv3_ui.cpp $(SRC)/*.hpp
	@mkdir -p $(dir $@); $(CXX) $(CXXFLAGS) -c $< -o $@
$(BUILD)/host_main.o: host_main.cpp $(SRC)/*.hpp
	@mkdir -p $(dir $@); $(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/v3_render: $(LVGL)/lvgl.h
	$(MAKE) --no-print-directory link

link: $(LV_OBJS) $(FONT_OBJS) $(BUILD)/icons.o $(BUILD)/ui.o $(BUILD)/host_main.o
	@$(CXX) -o $(BUILD)/v3_render $^ -lm

$(BUILD)/perf_main.o: perf_main.cpp $(SRC)/*.hpp
	@mkdir -p $(dir $@); $(CXX) $(CXXFLAGS) -g -c $< -o $@

perf-link: $(LV_OBJS) $(FONT_OBJS) $(BUILD)/icons.o $(BUILD)/ui.o $(BUILD)/perf_main.o
	@$(CXX) -o $(BUILD)/v3_perf $^ -lm

# rendering cost benchmark (computer proxy; see perf_main.cpp)
perf: $(LVGL)/lvgl.h
	@$(MAKE) --no-print-directory perf-link
	@mkdir -p out/perf; $(BUILD)/v3_perf out/perf/frames_wall.csv

render: $(LVGL)/lvgl.h
	@$(MAKE) --no-print-directory link
	$(BUILD)/v3_render out

sizes: $(LVGL)/lvgl.h
	@$(MAKE) --no-print-directory link
	@python3 ../../tools/v3/data_sizes.py $(BUILD)

clean:
	rm -rf $(BUILD) out
.PHONY: all model render link sizes clean perf perf-link
