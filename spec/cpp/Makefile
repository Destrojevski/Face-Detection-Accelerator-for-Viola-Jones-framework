TARGET	= facedetect.exe

SRCS	=  \
	main.cpp \
	tb_facedetect.cpp \
	image.cpp \
	image_ops.cpp \
	facedetect.cpp

HDRS	=  \
	tb_facedetect.h \
	image.h \
	facedetect.h \
	image_ops.h \
	define.h

CC	= g++
LINKER	= $(CC)
INCL	= -I"." -I"../../data"
CFLAGS	= -O1 -std=c++11
LDFLAGS	=
LIBS	= -lm
OBJS	= $(notdir $(addsuffix .o,$(basename $(SRCS))))

debug: CFLAGS += -g -DDEBUG
io: CFLAGS += -DIO

$(TARGET): $(OBJS)
	$(LINKER) -o "$@" $(LDFLAGS) $(OBJS) $(LIBS)

debug: $(OBJS)
	$(LINKER) -o $(TARGET) $(LDFLAGS) $(OBJS) $(LIBS)

io: $(OBJS)
	$(LINKER) -o $(TARGET) $(LDFLAGS) $(OBJS) $(LIBS)

image_ops.o: image_ops.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

image.o: image.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

main.o: main.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

facedetect.o: facedetect.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

tb_facedetect.o: tb_facedetect.cpp $(HDRS)
	$(CC) $(CFLAGS) $(INCL) -c $< -o $@

clean:
	rm -f *.o Output.pgm Face.pgm facenumber.txt $(TARGET)
