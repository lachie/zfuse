#include "fuse_interop.h"

uint64_t get_fh(struct fuse_file_info* fi) {
    return fi->fh;
}

void set_fh(struct fuse_file_info* fi, uint64_t fh) {
    fi->fh = fh;
    return;
}