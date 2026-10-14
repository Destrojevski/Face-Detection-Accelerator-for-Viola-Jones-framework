TARGET	= bit_analysis.exe

SRCS	=  \
	bit_analysis_multi.cpp \
	facedetect.cpp \
	image.cpp \
	image_ops.cpp

HDRS	=  \
	facedetect.h \
	fixedpoint.h \
	image.h \
	image_ops.h \
	define.h

CC	= g++
LINKER	= $(CC)
INCL	= -I"." -I"../../data"
CFLAGS	= -O2 -std=c++11
LDFLAGS	=
LIBS	= -lm
OBJS	= $(notdir $(addsuffix .o,$(basename $(SRCS))))

$(TARGET): $(OBJS)
	$(LINKER) -o "$@" $(LDFLAGS) $(OBJS) $(LIBS)

bit_analysis_multi.o: bit_analysis_multi.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

facedetect_fx.o: facedetect_fx.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

image.o: image.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

image_ops.o: image_ops.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

clean:
	rm -f *.o $(TARGET) bit_analysis_multi.csv bit_analysis_multi.txt
