#ifndef FUSE_INTEROP_H
#define FUSE_INTEROP_H

#define FUSE_USE_VERSION 31
#include <fuse.h>
#include <stdio.h>

uint64_t get_fh(struct fuse_file_info* fi);
void set_fh(struct fuse_file_info* fi, uint64_t fh);

#endif