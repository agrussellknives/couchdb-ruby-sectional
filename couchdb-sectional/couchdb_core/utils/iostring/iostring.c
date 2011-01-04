#include "ruby.h"
#include "ruby/io.h"

VALUE TiedWriter = Qnil;

extern VALUE rb_io_get_write_io(VALUE io);
extern void rb_io_check_initialized(rb_io_t *fptr);

// duplicated from io.c
#define GetWriteIO(io) rb_io_get_write_io(io)


// shamelessly copied from HEAD.

VALUE
rb_iostring_set_write_io(VALUE io, VALUE w)
{
    VALUE write_io;
    rb_io_check_initialized(RFILE(io)->fptr);
    if (!RTEST(w)) {
      w = 0;
    }
    else {
      GetWriteIO(w);
    }
    write_io = RFILE(io)->fptr->tied_io_for_writing;
    RFILE(io)->fptr->tied_io_for_writing = w;
    return write_io ? write_io : Qnil;
}
// checks the status of the read end without regard
// for the write end.  why would you want to close
// for reading while leaving it open for writing?
static VALUE
rb_iostring_closed_read(VALUE io)
{
    rb_io_t *fptr;
    fptr = RFILE(io)->fptr;
    rb_io_check_initialized(fptr);
    return 0 <= fptr->fd ? Qfalse : Qtrue;
}
// override of close_read
static VALUE
rb_iostring_close_read(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;

    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(io)) {
    rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    GetOpenFile(io, fptr);
    if (is_socket(fptr->fd, fptr->pathv)) {
#ifndef SHUT_RD
# define SHUT_RD 0
#endif
        if (shutdown(fptr->fd, SHUT_RD) < 0)
            rb_sys_fail_path(fptr->pathv);
        fptr->mode &= ~FMODE_READABLE;
        if (!(fptr->mode & FMODE_WRITABLE))
            return rb_io_close(io);
        return Qnil;
    }

    // need to skip this part and just close the reading
    // end.  this thing IS a duplex io, it just has two
    // non duplex ends
    write_io = GetWriteIO(io);
    if (io != write_io) {
        rb_io_t *wfptr;
        rb_io_fptr_cleanup(fptr, FALSE);
        GetOpenFile(write_io, wfptr);
        RFILE(io)->fptr = wfptr;
        RFILE(write_io)->fptr = NULL;
        rb_io_fptr_finalize(fptr);
        return Qnil;
    }

    if (fptr->mode & FMODE_WRITABLE) {
    rb_raise(rb_eIOError, "closing non-duplex IO for reading");
    }
    return rb_io_close(io);
}

void Init_iostring() {
  TiedWriter = rb_define_module("TiedWriter");
  rb_define_method(TiedWriter,"write_io=",rb_io_set_write_io,1);
  rb_define_method(TiedWriter,"write_io",rb_io_get_write_io,0);
  rb_define_method(TiedWriter,"closed_read?",rb_io_closed_read,0);
}
