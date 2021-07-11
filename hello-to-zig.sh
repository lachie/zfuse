
zig translate-c \
    -lc \
    -I./libfuse/include \
    ./libfuse/example/hello.c > hello.zig
    #-I/usr/include/x86_64-linux-gnu \
    #-D_FILE_OFFSET_BITS=64 \
    

# zig translate-c \
#     -lc \
#     -I/usr/include \
#     -I/usr/include/fuse \
#     -I/usr/include/x86_64-linux-gnu \
#     -D_FILE_OFFSET_BITS=64 fuse_operations.h > fo.zig