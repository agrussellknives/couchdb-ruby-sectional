#include "ruby.h"
#include "ruby/io.h"

VALUE TiedWriter = Qnil;

extern VALUE rb_io_get_write_io(VALUE io);
extern void rb_io_check_initialized(rb_io_t *fptr);

// duplicated from io.c
#define GetWriteIO(io) rb_io_get_write_io(io)
#define rb_sys_fail_path(path) rb_sys_fail(NIL_P(path) ? 0 : RSTRING_PTR(path))
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
// implemented in c for symmetrry more than anything else
static VALUE
rb_iostring_closed_write(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;
    write_io = GetWriteIO(io); 
    fptr = RFILE(write_io)->fptr;
    rb_io_check_initialized(fptr);
    return 0 <= fptr->fd ? Qfalse : Qtrue;
}

static void
iostring_check_security(VALUE io)
{
  if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(io)) 
    rb_raise(rb_eSecurityError, "Insecure: can't close");
}

static void
iostring_close_fd(rb_io_t *fptr)
{
  VALUE err = Qnil;
  if (fptr->fd < 0)
    rb_raise(rb_eIOError,"closed stream");

  if (close(fptr->fd) < 0 && NIL_P(err)) 
    err = INT2NUM(errno);

  fptr->fd = -1;
  fptr->stdio_file = 0;
  fptr->mode &= ~(FMODE_READABLE|FMODE_WRITABLE);
  
  if (!NIL_P(err)) {
    switch(TYPE(err)) {
      case T_FIXNUM:
      case T_BIGNUM:
        errno = NUM2INT(err);
        rb_sys_fail_path(fptr->pathv);

      default:
        rb_exc_raise(err);
    }
  }
}

// override of close_read
static VALUE 
rb_iostring_close_read(VALUE io)
{
  rb_io_t *fptr;
  
  iostring_check_security(io);
  fptr = RFILE(io)->fptr; 
  
  // close the reading end, but leave the writing end open
  // we don't clean up - raise an exception if it's already closed
  iostring_close_fd(fptr);
  return Qnil;
}

// override of close_write
static VALUE
rb_iostring_close_write(VALUE io)
{
  rb_io_t *fptr;
  VALUE write_io;

  iostring_check_security(io);
  write_io = GetWriteIO(io);
  fptr = RFILE(write_io)->fptr;
 
  // since tied is always something this should really comeup
  if (fptr->mode & FMODE_READABLE || NIL_P(write_io))
    rb_raise(rb_eIOError, "closing non-duplex IO for writing");
 
  // remove the tied_io so it doesn't confus the rest of ruby 
  iostring_close_fd(fptr);
  fptr = RFILE(io)->fptr;
  fptr->tied_io_for_writing=0;
  return Qnil;
}
// set the fileno to something specific.  mostly useful for
// dupping.  in fact, this is pretty much what the dup function does
// we just need to subvert it a bit.
static VALUE
rb_iostring_set_fileno(VALUE io, int fd)
{
  rb_io_t *fptr;
  fptr = GetOpenFile(io);
  fptr->fd = fd;
  return INT2FIXNUM(fd);
}

// return a hash of the fptr struct for debugging
static VALUE
rb_iostring_fptr(VALUE io)
{
  rb_io_t *fptr;
  VALUE hash = Qnil;
  fptr = RFILE(io)->fptr;
  hash = rb_hash_new();

  rb_hash_aset(hash,rb_str_new2("fd"),INT2NUM(fptr->fd));
  rb_hash_aset(hash,rb_str_new2("tied_io_for_writing"),fptr->tied_io_for_writing);
  return hash;
}

void Init_iostring() {
  TiedWriter = rb_define_module("TiedWriter");
  rb_define_method(TiedWriter,"write_io=",rb_iostring_set_write_io,1);
  rb_define_method(TiedWriter,"write_io",rb_io_get_write_io,0);
  rb_define_method(TiedWriter,"closed_read?",rb_iostring_closed_read,0);
  rb_define_method(TiedWriter,"closed_write?",rb_iostring_closed_write,0);
  rb_define_method(TiedWriter,"close_read",rb_iostring_close_read,0);
  rb_define_method(TiedWriter,"close_write",rb_iostring_close_write,0);
  rb_define_method(TiedWriter,"fptr",rb_iostring_fptr,0);
}
