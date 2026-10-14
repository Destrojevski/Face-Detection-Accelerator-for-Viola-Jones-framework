obj-m += vj_driver.o

# Build direktno na Zybo plocici, na kernelu koji trenutno radi.
# Zahtijeva kernel-devsrc pakete(CONFIG_kernel-devsrc sa vjezbi).
KDIR := /lib/modules/$(shell uname -r)/build

all:
	make -C $(KDIR) M=$(PWD) modules

clean:
	make -C $(KDIR) M=$(PWD) clean

install: all
	insmod vj_driver.ko

uninstall:
	rmmod vj_driver

.PHONY: all clean install uninstall
