SRC_DIR = src
BUILD_DIR = build
GEN_DIR = $(BUILD_DIR)/gen
OBJ_DIR = $(BUILD_DIR)/obj
BIN_DIR = $(BUILD_DIR)/bin
MAIN_FILE = main

#Statically or dynamically link to lua
#! WARNING !#
#If you link with a different lua version than `extern/lua-aot` (currently Lua 5.4.3, find out by doing `./extern/luaot/src/lua -v`)
#YOU WILL HAVE UNDEFINED AND BUGGY BEHAVIOUR!
BUILD_STATIC=1

LUA_LIBDIR=/usr/local/lib/
#Target for building lua
ifeq ($(shell uname -o),Cygwin)
	LUA_TARGET=posix
else
	LUA_TARGET=guess
endif

CC=cc
LD=$(CC)

LUAOT_DIR=./extern/lua-aot
LUAOT=$(LUAOT_DIR)/src/luaot
LUA=$(LUAOT_DIR)/src/lua

ARGPARSE_DIR=./extern/argparse/src

TL_VENDORED=1
ifeq ($(TL_VENDORED),1)
	TL=./extern/experimental/tl-nolfs/tl
	# If we are vendored also use the vendored argparse
	TL_ENV=LUA_PATH="$(ARGPARSE_DIR)/?.lua" $(LUA)
else
	TL=tl
	TL_ENV=
endif


CFLAGS=-Os
LDFLAGS=
ifeq ($(BUILD_STATIC),1)
	LDFLAGS += -L$(LUAOT_DIR)/src -llua
else
	LDFLAGS += -L$(LUA_LIBDIR) -llua
endif

LDFLAGS += -lc -lm -ldl

TLFLAGS=
LUAOTFLAGS=
LUAOT_MAIN_FLAGS=-i posix -e

TEAL_FILES = $(wildcard $(SRC_DIR)/*.tl)
GENERATED_LUA_FILES = $(TEAL_FILES:$(SRC_DIR)/%.tl=$(GEN_DIR)/%.lua)

#Generated by LuAOT from lua files
GENERATED_C_FILES = $(TEAL_FILES:$(SRC_DIR)/%.tl=$(GEN_DIR)/%.c)

OBJECT_FILES = $(GENERATED_C_FILES:$(GEN_DIR)/%.c=$(OBJ_DIR)/%.o)

.PHONY: all clean release debug cfiles objects luaot shared run check-lua teal patch-luaot
# Just the lua files
debug: $(GENERATED_LUA_FILES)

all: release
clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) -C $(LUAOT_DIR) clean

luaot: $(LUAOT)
teal: $(TEAL)

cfiles: $(GENERATED_C_FILES)
objects: $(OBJECT_FILES)

release: check-lua $(BIN_DIR)/$(MAIN_FILE)

#Make `release` but with` BUILD_STATIC=0`
shared:
	$(MAKE) release BUILD_STATIC=0

run: debug
	$(TL_ENV) $(TL) run src/$(MAIN_FILE).tl


ifneq ($(LUA),$(LUAOT_DIR)/src/lua)
check-lua: $(LUAOT)
	./check-lua.sh $(LUA) $(LUAOT_DIR)/src/lua
else
check-lua:
endif

patch-luaot: internal-package-searcher.patch
	@printf "\x1b[1;35mPatching LuaOT...\x1b[0m\n"
#	it actually does patch, i dont know why it says it fails
	@-patch -f -s $(LUAOT_DIR)/src/luaot.c < $<


#git submodule, run `make guess` in that directory to build it
$(LUAOT): patch-luaot
	@printf "\x1b[1;35mCompiling LuaOT...\x1b[0m\n"
	$(MAKE) -C $(LUAOT_DIR) $(LUA_TARGET)

#first, a rule for compiling teal files to lua
#vendored installations need to also have luaot already built, so add it as a dependency
ifeq ($(TL_VENDORED),1)
$(GEN_DIR)/%.lua: $(SRC_DIR)/%.tl $(LUAOT)
else
$(GEN_DIR)/%.lua: $(SRC_DIR)/%.tl
endif
	@printf "\x1b[1;35mTranspiling \x1b[1;32m$<\x1b[1;35m to \x1b[1;32m$@\x1b[0m\n"
	@mkdir -p $(GEN_DIR)
	$(TL_ENV) $(TL) -I$(SRC_DIR) $(TLFLAGS) gen $< -o $@

#then, a rule for compiling lua files to c, if the file is MAIN_FILE then we need to use the -e -i flags aswell
#use -m to specify the module name, which should be basename of the file
$(GEN_DIR)/%.c: $(GEN_DIR)/%.lua $(LUAOT)
	@printf "\x1b[1;35mGenerating C source from \x1b[1;32m$<\x1b[1;35m to \x1b[1;32m$@\x1b[0m\n"
	@mkdir -p $(GEN_DIR)
	$(LUAOT) $(LUAOTFLAGS) -m $(basename $(notdir $<)) -o $@ $<

$(GEN_DIR)/$(MAIN_FILE).c: $(GEN_DIR)/$(MAIN_FILE).lua $(LUAOT)
	@printf "\x1b[1;35mGenerating C source from \x1b[1;32m$<\x1b[1;35m to \x1b[1;32m$@\x1b[0m\n"
	@mkdir -p $(GEN_DIR)
	$(LUAOT) $(LUAOT_MAIN_FLAGS) -m $(basename $(notdir $<)) -o $@ $<

#then, a rule for compiling c files to object files
$(OBJ_DIR)/%.o: $(GEN_DIR)/%.c
	@printf "\x1b[1;35mCompiling \x1b[1;32m$<\x1b[1;35m to \x1b[1;32m$@\x1b[0m\n"
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -I$(LUAOT_DIR)/src -c $< -o $@

#finally, a rule for linking object files to an executable
$(BIN_DIR)/$(MAIN_FILE): $(OBJECT_FILES)
	@printf "\x1b[1;35mLinking \x1b[1;32m$@\x1b[0m\n"
	@mkdir -p $(BIN_DIR)
	$(LD) $^ -o $@ $(LDFLAGS)
