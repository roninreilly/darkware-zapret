/* Copy untrusted user list data without following symlinks, including ancestors.
 * This helper never executes data. Destination must be a new root staging file.
 * Copyright (c) 2026 Darkware Zapret contributors. MIT license, see ../LICENSE. */
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

static int open_nofollow(const char *path) {
    if (path[0] != '/' || strlen(path) >= PATH_MAX) { errno = EINVAL; return -1; }
    char copy[PATH_MAX];
    strcpy(copy, path + 1);
    int dir = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dir < 0) return -1;
    char *state = NULL, *part = strtok_r(copy, "/", &state);
    while (part) {
        if (!strcmp(part, ".") || !strcmp(part, "..")) { close(dir); errno=EINVAL; return -1; }
        char *next = strtok_r(NULL, "/", &state);
        int fd = openat(dir, part, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (next ? O_DIRECTORY : O_NONBLOCK));
        close(dir);
        if (fd < 0) return -1;
        dir = fd;
        part = next;
    }
    return dir;
}
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "Usage: snapshot-list source destination expectedOwnerUID\n"); return 2; }
    char *end = NULL;
    unsigned long expected = strtoul(argv[3], &end, 10);
    if (!argv[3][0] || *end || expected > UINT_MAX) return 2;
    int source = open_nofollow(argv[1]);
    struct stat st;
    const off_t limit = 16 * 1024 * 1024;
    if (source < 0 || fstat(source, &st) || !S_ISREG(st.st_mode) || st.st_uid != (uid_t)expected || st.st_size < 0 || st.st_size > limit) {
        fprintf(stderr, "List rejected: symlink, non-regular file, unexpected owner or excessive size.\n");
        if (source >= 0) close(source);
        return 1;
    }
    int dest = open(argv[2], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (dest < 0) { perror("create snapshot"); close(source); return 1; }
    char buf[16384]; off_t total=0; int result=0;
    for (;;) {
        ssize_t count = read(source, buf, sizeof(buf));
        if (count < 0) { if (errno==EINTR) continue; result=1; break; }
        if (!count) break;
        total += count;
        if (total > limit) { result=1; break; }
        for (ssize_t done=0; done<count;) {
            ssize_t written=write(dest, buf+done, (size_t)(count-done));
            if (written<0 && errno==EINTR) continue;
            if (written<=0) { result=1; break; }
            done += written;
        }
        if (result) break;
    }
    if (close(dest)) result=1;
    close(source);
    if (result) { unlink(argv[2]); fprintf(stderr,"List snapshot failed.\n"); }
    return result;
}
