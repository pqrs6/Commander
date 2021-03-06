# Commander Makefile for use with EITHER the planck
# module build system OR a set of stand-alone
# config files.  Default make target prints help.
#
# This makefile requires the use of GNU make or
# compatible tools that allow the substitution
# operator ":=".
#

NOW := $(shell date +%Y%m%d-%H%M)
DIR := commander_$(NOW)

TOPDIR := $(shell pwd)
export TOPDIR


ifdef COMMANDER
	include $(TOPDIR)/config/config.$(COMMANDER)
	ifndef INSTALL
		INSTALL := $(TOPDIR)/install_$(COMMANDER)
	endif
else
	$(error COMMANDER undefined)UNDEFINED
endif

ifndef MAKE
	export MAKE := make
endif
ifndef AR
	export AR := ar
endif
ifndef ARFLAGS
	export ARFLAGS := crv
endif
ifndef RANLIB
	export RANLIB := ranlib
endif
ifndef CTAR
	export CTAR := tar czvf
endif
ifndef F90
	export F90 := f90
endif
ifndef MPF90
	export MPF90 := mpif90
endif
ifndef F90FLAGS
	export F90FLAGS := -g -O2
endif
ifndef MPF77
	export MPF77 := mpif77
endif
ifndef FFLAGS
	export FFLAGS := -g -O2
endif
ifndef MPCC
	export MPCC := cc
endif
ifndef CFLAGS
	export CFLAGS := -g -O2
endif
ifndef MPCXX
	export MPCXX := c++
endif
ifndef CXXFLAGS
	export CXXFLAGS := -g -O2
endif
ifndef LDFLAGS
	export LDFLAGS := -lm
endif
ifndef FORTRAN_UPPER
	export FORTRAN_UPPER := 0
endif
ifndef CFITSIO_LINK
	export CFITSIO_LINK := -L/usr/local/lib -lcfitsio
endif
ifndef LAPACK_LINK
	export LAPACK_LINK := #-L/usr/local/lib -llapack -lblas
endif


export F90COMP := $(F90FLAGS) $(LAPACK_INCLUDE) $(CFITSIO_INCLUDE) $(HEALPIX_INCLUDE) $(HDF_INCLUDE)
export FCOMP := $(FFLAGS)  $(LAPACK_INCLUDE) $(CFITSIO_INCLUDE) $(HEALPIX_INCLUDE)
export CCOMP := $(CFLAGS)  $(LAPACK_INCLUDE) $(CFITSIO_INCLUDE) $(HEALPIX_INCLUDE)
export LINK := -L. -lcommander $(SHARP_LINK) $(HEALPIX_LINK) $(CFITSIO_LINK) $(LAPACK_LINK) $(HDF_LINK) $(LDFLAGS) $(F90OMPFLAGS) 
export TEMPITA := "$(TOPDIR)/src/python/tempita_proc.py"


all : commander 

commander : 
	@cd src/commander; $(MAKE)

camb : 
	@cd src/camb; $(MAKE)

messcomm : 
	@cd src/messcomm; $(MAKE) 

clean :
	@cd src/commander; $(MAKE) clean

