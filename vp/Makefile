TARGET	= facedetect.exe

SRCS	=  \
	srcs/scmain.cpp \
	srcs/tb_vp.cpp \
	srcs/image.cpp \
	srcs/image_ops.cpp \
	srcs/ddr3.cpp \
	srcs/bram_mem.cpp \
	srcs/vp.cpp \
	srcs/ic.cpp \
	srcs/ip.cpp

HDRS	=  \
	srcs/tb_vp.hpp \
	srcs/image.h \
	srcs/image_ops.h \
	srcs/ip.hpp \
	srcs/bram_mem.hpp \
	srcs/ddr3.hpp \
	srcs/vp.hpp \
	srcs/ic.hpp \
	srcs/define.h \
	srcs/vp_addr.hpp \
	srcs/ip_consts.hpp

ifneq (, $(wildcard /bin/uname))
CPU_ARCH = $(shell /bin/uname -m)
endif

ifeq ($(CPU_ARCH),x86_64)
CWB_LIB   = $(CYBER_PATH)/lib64
ARCH_FLAG = 
else
CWB_LIB   = $(CYBER_PATH)/lib
ARCH_FLAG = -m32
endif

ifdef CYBER_SYSTEMC_TARGET_ARCH
CWB_SC_ARCH = $(CYBER_SYSTEMC_TARGET_ARCH)
else
ifeq (, $(findstring Windows,$(OS)))
ifeq ($(CPU_ARCH),x86_64)
CWB_SC_ARCH = linux64
else
CWB_SC_ARCH = linux
endif
else
CWB_SC_ARCH = mingw
endif
endif

ifdef CYBER_SYSTEMC_HOME
CWB_SC_HOME = $(CYBER_SYSTEMC_HOME)
else
CWB_SC_HOME = $(CYBER_PATH)/osci
endif

CWB_SC_LIB = -L/usr/lib/x86_64-linux-gnu -lsystemc

EMPTY	=
SPACE	= $(EMPTY) $(EMPTY)
ifeq (, $(wildcard  $(subst $(SPACE),\$(SPACE),$(CYBER_PATH))/gcc/bin))
CC	= g++
RM	= rm
else
CC	= "$(CYBER_PATH)/gcc/bin/g++"
RM	= "$(CYBER_PATH)/gcc/bin/rm"
endif
LINKER	= $(CC)
INCL	= -I"." -I"srcs" -I"libs" -I"../data"
CFLAGS	= $(ARCH_FLAG) -O1
LDFLAGS	= $(ARCH_FLAG)
LIBS	= -lm $(CWB_SC_LIB)  -Wl,-rpath="$(CWB_LIB)"
OBJS	= $(notdir $(addsuffix .o,$(basename $(SRCS))))
debug: CFLAGS += -g -DDEBUG
wave: CFLAGS += -DWAVE_DUMP

$(TARGET) : $(OBJS)
	$(LINKER) -o "$@" $(LDFLAGS) $(OBJS) $(LIBS)

debug: $(OBJS)
	$(LINKER) -o $(TARGET) $(LDFLAGS) $(OBJS) $(LIBS)
	
wave:  $(OBJS) 
	$(LINKER) -o $(TARGET) $(LDFLAGS) $(OBJS) $(LIBS)

scmain.o: srcs/scmain.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

tb_vp.o: srcs/tb_vp.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

image_ops.o: srcs/image_ops.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

image.o: srcs/image.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

ip.o: srcs/ip.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

ddr3.o: srcs/ddr3.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

bram_mem.o: srcs/bram_mem.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

ic.o: srcs/ic.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

vp.o: srcs/vp.cpp $(HDRS)
	$(CC) $(CFLAGS) $(CWB_SC_INCL) $(INCL) -c $< -o $@

clean:
	rm -f *.o Output.pgm Face.pgm *.vcd $(TARGET)
