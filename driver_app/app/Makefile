CC      = gcc
CFLAGS  = -Wall -Wextra -O2
LDFLAGS = -lm

TARGET  = vj_app
SRC     = vj_app.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
