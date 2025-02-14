# Generic Makefile for GEMMA
#
# Supported platforms
#
#       Unix / Linux               LNX (default)
#       Mac                        OSX
#       GNU Guix                   GUIX (set to profile)
#
# Compilation options
#       static compilation         FORCE_STATIC
#
# Examples:
#
#    Make GEMMA on Linux without OPENBLAS support:
#
#      make WITH_OPENBLAS=
#
#    Disable debug info and checks (release mode is slightly faster)
#
#      make debug
#
#    Force static compilation
#
#      make static
#
#    Static build may require some extra flags
#
#      make WITH_GFORTRAN=1 EXTRA_FLAGS=-L/gnu/store/741057r2x06zwg6zcmqmdyv51spm6n9i-gfortran-7.5.0-lib/lib static
#
#    Run tests with
#
#      make check
#
#    Run quick (development) tests with
#
#      make fast-check
#
#    Run full (lengthy) tests with
#
#      make check-all
#
#    To compile with CLANG
#
#      make CXX=clang++
#
#    See also the INSTALL.md document in the source tree at
#
#      https://github.com/genetics-statistics/GEMMA/blob/master/INSTALL.md

GEMMA_VERSION = $(shell cat ./VERSION)

# Set this variable to either LNX or OSX
ifeq ($(OS),Windows_NT)
  SYS = WIN
  VGEN = scripts/gen_version_info.cmd
else
  UNAME_S := $(shell uname -s)
  ifeq ($(UNAME_S),Darwin)
    SYS = OSX
  else
    SYS = LNX # default to linux
  endif
  VGEN = scripts/gen_version_info.sh
endif

# Leave blank after "=" to disable; put "= 1" to enable
DIST_NAME              = gemma-$(GEMMA_VERSION)
DEBUG                  = 1                # DEBUG mode, set DEBUG=0 for a release
PROFILING              =                  # Add profiling info
SHOW_COMPILER_WARNINGS =
WITH_OPENBLAS          = 1                # Without OpenBlas uses LAPACK
WITH_ATLAS             =                  # In place of OpenBlas(?)
WITH_LAPACK            =                  # Force linking LAPACK (if OpenBlas lacks it)
WITH_GSLCBLAS          =                  # Force linking gslcblas (if OpenBlas lacks it)
WITH_GFORTRAN          =                  # Add -lgfortran (if OpenBlas does not pull it in)
OPENBLAS_LEGACY        =                  # Using older OpenBlas
FORCE_STATIC           =                  # Static linking of libraries
GCC_FLAGS              = -DHAVE_INLINE -pthread -Wall -std=gnu++11 # extra flags -Wl,--allow-multiple-definition
EXTRA_FLAGS            =

GSL_INCLUDE_PATH =
ifeq ($(SYS), WIN)
  GSL_INCLUDE_PATH = -isystemc:/MinGW/include -LC:/MinGW/lib
  OPENBLAS_INCLUDE_PATH = ../OpenBLAS-v0.2.19-Win64-int32/include -L../OpenBLAS-v0.2.19-Win64-int32/lib
else
  OPENBLAS_INCLUDE_PATH = /usr/local/opt/openblas/include
  ifndef GUIX
    ifdef GUIX_ENVIRONMENT
      GUIX=$(GUIX_ENVIRONMENT)
    endif
  endif
  ifdef GUIX
    # Effectively disable paths for GNU Guix
    OPENBLAS_INCLUDE_PATH = .
    # RPATH = -Xlinker --rpath=$(GUIX)/lib
    ifdef FORCE_STATIC
      LIBS = -L$(GUIX)/lib
    endif
    GUIX_PROFILE =$(realpath $(GUIX))
  endif
endif

# --------------------------------------------------------------------
# Edit below this line with caution
# --------------------------------------------------------------------

BIN_DIR  = ./bin
SRC_DIR  = ./src
TEST_SRC_DIR  = ./test/src

ifdef CXX # CXX defined in environment
  CPP = $(CXX)
  CC = $(CXX)
else
  CPP = g++
endif

ifeq ($(CPP), clang++)
  GCC_FLAGS=-std=c++11 -isystem$(OPENBLAS_INCLUDE_PATH)
  ifdef GUIX
    CPPFLAGS += -I$(GUIX)/include/c++ -I$(GUIX)/include/c++/x86_64-unknown-linux-gnu
  endif
endif

ifdef WITH_OPENBLAS
  OPENBLAS=1
  # WITH_LAPACK =  # OPENBLAS usually includes LAPACK
  CPPFLAGS += -DOPENBLAS -isystem$(OPENBLAS_INCLUDE_PATH)
  ifdef OPENBLAS_LEGACY
    # Legacy version (mostly for Travis-CI)
    CPPFLAGS += -DOPENBLAS_LEGACY
  endif
else
  ifdef WITH_ATLAS
    CPPFLAGS += -DUSE_BLAS=atlas
  endif
endif

ifneq ($(CXX), clang++)
  # Clang does not like these switches
  debug check fast-check: CPPFLAGS += -Og -Wfatal-errors -Wextra -Wpedantic
endif

debug check fast-check: CPPFLAGS += -g $(GCC_FLAGS) $(GSL_INCLUDE_PATH) -Isrc

profile: CPPFLAGS += -g $(GCC_FLAGS) $(GSL_INCLUDE_PATH) -Isrc

release: CPPFLAGS += -DNDEBUG -g -O3 $(GCC_FLAGS) $(GSL_INCLUDE_PATH) -Isrc

static: CPPFLAGS += -DNDEBUG -g $(GCC_FLAGS) $(GSL_INCLUDE_PATH) -Isrc


ifeq ($(SYS), WIN)
  CPPFLAGS += -Duint="unsigned int" -D__CRT__NO_INLINE -D__STRING="__STRINGIFY" -DWINDOWS -DWITH_GSLCBLAS=1
endif

ifdef SHOW_COMPILER_WARNINGS
  CPPFLAGS += -Wall
endif

static: CPPFLAGS += -static

LIBS += -lgsl -lz
ifdef WITH_OPENBLAS
  LIBS += -lopenblas
  ifeq ($(SYS), OSX)
    ifdef WITH_OPENBLAS
      LIBS += -Wl,-L/usr/local/opt/openblas/lib
    endif
  endif
else
  LIBS += -latlas -lcblas -llapack -lblas
endif
ifdef WITH_GSLCBLAS
  LIBS += -lgslcblas
endif
ifdef WITH_GFORTRAN
  LIBS += -lgfortran -lquadmath
endif
ifdef EXTRA_FLAGS
  LIBS += $(EXTRA_FLAGS)
endif

profile: LIBS += -Wl,--no-as-needed -lprofiler -Wl,--as-needed

.PHONY: all test

OUTPUT = $(BIN_DIR)/gemma

# Detailed libary paths, D for dynamic and S for static

ifdef WITH_LAPACK
  LIBS += -llapack
endif
LIBS_OSX_D_LAPACK = -framework Accelerate

ifdef WITH_LAPACK
  ifeq ($(SYS), OSX)
    LIBS += $(LIBS_OSX_D_LAPACK)
    ifdef WITH_OPENBLAS
      LIBS += -Wl,-L/usr/local/opt/openblas/lib
    endif
  endif
endif

HDR          = $(sort $(wildcard src/*.h)) ./src/version.h
SOURCES      = $(sort $(wildcard src/*.cpp))

# all
OBJS = $(SOURCES:.cpp=.o)

all: release

release: $(OUTPUT)

static: $(OUTPUT)

debug profile: $(OUTPUT)

./src/version.h: ./VERSION
	$(shell bash $(VGEN) $(GUIX_PROFILE) > src/version.h)

$(OUTPUT): $(OBJS)
	$(CPP) $(CPPFLAGS) $(OBJS) $(LIBS) -o $(OUTPUT)

$(OBJS): $(HDR)

.SUFFIXES : .cpp .c .o $(SUFFIXES)

./bin/unittests-gemma: $(TEST_SRC_DIR)/unittests-main.o $(TEST_SRC_DIR)/unittests-math.o $(OBJS)
	$(CPP) $(CPPFLAGS) $(TEST_SRC_DIR)/unittests-main.o  $(TEST_SRC_DIR)/unittests-math.o $(filter-out src/main.o, $(OBJS)) $(LIBS) -o ./bin/unittests-gemma

unittests: all ./bin/unittests-gemma
	./bin/unittests-gemma

fast-check: all unittests
	rm -vf output/*
	ruby -Eutf-8 -Itest ./test/dev_tests.rb | tee ./dev_test.log

# Note the following tests are not robust for different architectures
old-check: all unittests
	rm -vf test/output/*
	cd test && ./dev_test_suite.sh | tee ../test.log
	grep -q 'success rate: 100%' test.log

# Note the following tests are not robust for different architectures
slow-check: all
	rm -vf test/output/*
	cd test && ./test_suite.sh | tee ../test.log
	grep -q 'success rate: 100%' test.log

# Note the following tests are not robust for different architectures
lengthy-check: all
	rm -vf test/output/*
	cd test && ./lengthy_test_suite.sh | tee ../lengthy_test.log
	grep -q 'success rate: 100%' lengthy_test.log

check: fast-check

clean:
	rm -vf $(SRC_DIR)/*.o
	rm -vf $(SRC_DIR)/*~
	rm -vf $(TEST_SRC_DIR)/*.o
	rm -vf $(OUTPUT)
	rm -vf ./bin/unittests-gemma

DIST_COMMON = *.md LICENSE VERSION Makefile
DIST_SUBDIRS = src doc example bin

tar: version all
	@echo "Creating $(DIST_NAME)"
	mkdir -p ./$(DIST_NAME)
	cp $(DIST_COMMON) ./$(DIST_NAME)/
	cp -r $(DIST_SUBDIRS) ./$(DIST_NAME)/
	tar cvzf $(DIST_NAME).tar.gz ./$(DIST_NAME)/
	rm -r ./$(DIST_NAME)
