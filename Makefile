BUILD:=build
SRC:=src

MULTIBOOT2:=0x10000
ENTRYPOINT:=0x10040

CFLAGS:= -m32 # 32 位的程序
CFLAGS+= -fno-builtin	# 不需要 gcc 内置函数
CFLAGS+= -nostdinc		# 不需要标准头文件
CFLAGS+= -fno-pic		# 不需要位置无关的代码  position independent code
CFLAGS+= -fno-pie		# 不需要位置无关的可执行程序 position independent executable
CFLAGS+= -nostdlib		# 不需要标准库
CFLAGS+= -fno-stack-protector	# 不需要栈保护
CFLAGS:=$(strip ${CFLAGS})

DEBUG:= -g
INCLUDE:=-I$(SRC)/include

$(BUILD)/boot/%.bin: $(SRC)/boot/%.asm
	$(shell mkdir -p $(dir $@))
	nasm -f bin $< -o $@

$(BUILD)/%.o: $(SRC)/%.asm
	$(shell mkdir -p $(dir $@))
	nasm -F dwarf -f elf32 $(DEBUG) $< -o $@

$(BUILD)/%.o: $(SRC)/%.c
	$(shell mkdir -p $(dir $@))
	gcc $(CFLAGS) $(DEBUG) $(INCLUDE) -c $< -o $@

LDFLAGS:= -m elf_i386 \
		-static \
		-Ttext $(ENTRYPOINT)\
		--section-start=.multiboot2=$(MULTIBOOT2)
LDFLAGS:=$(strip ${LDFLAGS})

$(BUILD)/kernel.bin: \
	$(BUILD)/kernel/start.o \
	$(BUILD)/kernel/main.o \
	$(BUILD)/kernel/io.o \
	$(BUILD)/kernel/console.o \
	$(BUILD)/kernel/printk.o \
	$(BUILD)/kernel/assert.o \
	$(BUILD)/kernel/debug.o \
	$(BUILD)/kernel/global.o \
	$(BUILD)/kernel/task.o \
	$(BUILD)/kernel/thread.o \
	$(BUILD)/kernel/mutex.o \
	$(BUILD)/kernel/gate.o \
	$(BUILD)/kernel/schedule.o \
	$(BUILD)/kernel/interrupt.o \
	$(BUILD)/kernel/handler.o \
	$(BUILD)/kernel/clock.o \
	$(BUILD)/kernel/time.o \
	$(BUILD)/kernel/rtc.o \
	$(BUILD)/kernel/memory.o \
	$(BUILD)/kernel/keyboard.o \
	$(BUILD)/lib/bitmap.o \
	$(BUILD)/lib/list.o \
	$(BUILD)/lib/fifo.o \
	$(BUILD)/lib/string.o \
	$(BUILD)/lib/vsprintf.o \
	$(BUILD)/lib/stdlib.o \
	$(BUILD)/lib/syscall.o \

	$(shell mkdir -p $(dir $@))
	ld ${LDFLAGS} $^ -o $@

$(BUILD)/system.bin: $(BUILD)/kernel.bin
	objcopy -O binary $< $@

$(BUILD)/system.map: $(BUILD)/kernel.bin
	nm $< | sort > $@

$(BUILD)/master.img: $(BUILD)/boot/boot.bin \
	$(BUILD)/boot/loader.bin \
	$(BUILD)/system.bin \
	$(BUILD)/system.map \

	cp resource/base.img $@
	dd if=$(BUILD)/boot/boot.bin of=$@ bs=512 count=1 conv=notrunc
	dd if=$(BUILD)/boot/loader.bin of=$@ bs=512 count=4 seek=2 conv=notrunc
	test -n "$$(find $(BUILD)/system.bin -size -100k)"
	dd if=$(BUILD)/system.bin of=$@ bs=512 count=200 seek=10 conv=notrunc

$(BUILD)/kernel.iso : $(BUILD)/kernel.bin $(SRC)/utils/grub.cfg
	grub-file --is-x86-multiboot2 $<
	mkdir -p $(BUILD)/iso/boot/grub
	cp $< $(BUILD)/iso/boot
	cp $(SRC)/utils/grub.cfg $(BUILD)/iso/boot/grub
	grub-mkrescue -o $@ $(BUILD)/iso

base:
	yes | qemu-img create resource/base.img 16M

image: 
	$(call docker_env, make $(BUILD)/master.img)

iso: 
	$(call docker_env, make $(BUILD)/kernel.iso)

QEMU:= qemu-system-i386 \
	-m 32M \
	-audiodev coreaudio,id=coreaudio \
	-machine pcspk-audiodev=coreaudio \
	-rtc base=localtime \

QEMU_DISK:=-boot c \
	-drive file=$(BUILD)/master.img,if=ide,index=0,media=disk,format=raw \

QEMU_CDROM:=-boot d \
	-drive file=$(BUILD)/kernel.iso,media=cdrom \

QEMU_DEBUG:= -s -S

run: 
	$(QEMU) $(QEMU_DISK)

runb: 
	$(QEMU) $(QEMU_CDROM)

rung: 
	$(QEMU) $(QEMU_DISK) $(QEMU_DEBUG)

# bochs -> 4 -> resource/bochsrc -> 7 -> vi disk
bochs: 
	bochs -q -f resource/bochsrc -unlock

bochsb: $(BUILD)/kernel.iso
	bochs -q -f resource/bochsrc.grub -unlock

dev-start:
	docker run -d --rm \
	--network=host \
	--name=demo-os \
	-v ${PWD}:/work \
	-w /work \
	os-dev:v1.0.0 bash -c "sleep infinity"

dev-stop:
	docker stop demo-os

clean:
	rm -rf build
########################function############################
########$(call docker_env, sleep 10)#########
define docker_env
	docker run --rm \
		-v ${PWD}:/work \
		-w /work \
		os-dev:v1.0.0 bash -c "$(1)"
endef